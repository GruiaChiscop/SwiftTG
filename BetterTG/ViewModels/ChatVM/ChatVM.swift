// ChatVM.swift

import Combine
import SwiftUI
import TDLibKit

@MainActor @Observable final class ChatVM {
    // MARK: Lifecycle

    init(
        customChat: CustomChat,
        initialMessageId: Int64? = nil,
        movesAccessibilityFocusToInitialMessage: Bool = false,
        messageTopic: MessageTopic? = nil,
        service: any TelegramService = TDLib.shared.service,
    ) {
        self.customChat = customChat
        self.chatId = customChat.chat.id
        self.initialMessageId = initialMessageId
        self.movesAccessibilityFocusToInitialMessage = movesAccessibilityFocusToInitialMessage
        self.messageTopic = messageTopic
        if case .messageTopicForum = messageTopic {
            // A forum topic has its own read state; the enclosing chat's counters aggregate every
            // topic and would position the topic at the wrong unread boundary.
            self.initialUnreadCount = 0
            self.initialLastReadInboxMessageId = 0
            self.conversationUnreadCount = 0
        } else if case .messageTopicThread = messageTopic {
            // Comment threads likewise expose a thread-specific unread count. TDLib doesn't
            // expose a last-read id for them, so ChatView derives the boundary from that count.
            self.initialUnreadCount = 0
            self.initialLastReadInboxMessageId = 0
            self.conversationUnreadCount = 0
        } else {
            self.initialUnreadCount = customChat.unreadCount
            self.initialLastReadInboxMessageId = customChat.lastReadInboxMessageId
            self.conversationUnreadCount = customChat.unreadCount
        }
        self.service = service
        self.composer = MessageComposer(
            chatId: customChat.chat.id,
            service: service,
            draftMessage: customChat.draftMessage,
            topicId: messageTopic,
        )
        self.voiceRecorder = VoiceRecordingController(
            chatId: customChat.chat.id,
            service: service,
            topicId: messageTopic,
        )
        self.videoRecorder = TelegramVideoNoteRecorder()
        self.conversationSearch = TelegramConversationSearchStore(service: service)
        self.favoriteStickers = TelegramFavoriteStickersStore(service: service)
        self.typingActionManager = TelegramTypingActionManager(
            service: service,
            chatId: customChat.chat.id,
            topicId: messageTopic,
            isEnabled: !customChat.isSavedMessages && customChat.supergroup?.isChannel != true,
        )
        self.onlineStatus =
            if let user = customChat.user {
                getOnlineStatus(from: user.status)
            } else {
                conversationCommunityStatus(for: customChat)
            }
    }

    deinit {
        conversationStatusTask?.cancel()
        conversationPreparationTask?.cancel()
        presenceExpiryTask?.cancel()
        pinnedMessagesTask?.cancel()
        guard hasStarted else { return }
        let chatId = chatId
        let service = service
        Task { _ = try? await service.closeChat(chatId: chatId) }
    }

    // MARK: Internal

    /// Telegram-iOS opens a chat around a bounded 44-message history view. Keeping the same-sized
    /// initial window prevents both a one-message flash and unbounded eager pagination.
    static let initialHistoryWindowSize = 44

    var customChat: CustomChat
    /// Mirrors `customChat.chat.id` as a plain `Int64` so `deinit` (always nonisolated, even on a
    /// `@MainActor` class) can read it without hopping actors - `customChat` itself is a mutable,
    /// non-`Sendable` property and can't be touched from there.
    let chatId: Int64
    let initialMessageId: Int64?
    let movesAccessibilityFocusToInitialMessage: Bool
    /// When set, this `ChatVM` is scoped to a single thread (channel-post comments) or forum topic
    /// within `customChat`, rather than the chat's whole history - `nil` preserves the original
    /// full-chat behavior everywhere below.
    let messageTopic: MessageTopic?
    var initialUnreadCount: Int
    var initialLastReadInboxMessageId: Int64
    var conversationUnreadCount: Int

    let composer: MessageComposer
    let voiceRecorder: VoiceRecordingController
    let videoRecorder: TelegramVideoNoteRecorder
    let conversationSearch: TelegramConversationSearchStore
    let favoriteStickers: TelegramFavoriteStickersStore
    let typingActionManager: TelegramTypingActionManager

    var actionStatus = ""
    var isJoiningChat = false
    var onlineStatus = ""
    /// From `updateChatOnlineMemberCount` while the chat is open - TDLib only reports it for
    /// groups (and only up to a size cap), 0 otherwise.
    var onlineMemberCount = 0

    var highlightedMessageId: Int64?
    var scrollRequestMessageId: Int64?
    var accessibilityFocusRequestMessageId: Int64?
    var navigationError: String?
    var messageActionError: String?
    var messagePendingForward: CustomMessage?
    var messages = [CustomMessage]()
    var initialMessagesLoaded = false
    var pinnedMessages = [Message]()
    var isLoadingPinnedMessages = false
    var pinnedMessagesError: String?
    var scheduledMessages = [Message]()
    var isLoadingScheduledMessages = false
    var scheduledMessagesError: String?
    var detectedChatLanguage: String?
    var isChatTranslationEnabled = false
    /// The chat's video chat (group voice chat / channel live stream) and the `GroupCall` behind it,
    /// kept live from `updateChatVideoChat` / `updateGroupCall`. An empty `groupCallId` means none.
    /// See `ChatVM+VideoChat`.
    var videoChat = VideoChat(defaultParticipantId: nil, groupCallId: 0, hasParticipants: false)
    var videoChatCall: GroupCall?
    @ObservationIgnored var dateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm"
        return dateFormatter
    }()

    @ObservationIgnored var loadingMessagesTask: Task<Void, Never>?
    @ObservationIgnored var hasReachedBeginningOfHistory = false
    @ObservationIgnored let service: any TelegramService
    @ObservationIgnored var appliedMessageSnapshotVersion: UInt64?
    @ObservationIgnored var latestMessageSnapshot: TelegramMessageSnapshot?
    @ObservationIgnored var renderedMessages = [Int64: CustomMessage]()
    @ObservationIgnored var provisionalMessageIds = Set<Int64>()
    /// Ids explicitly paged in or received live by this ChatVM instance. The shared message store
    /// retains a chat's full history for the app's lifetime, so reconcile/render only ever
    /// consider this bounded set rather than everything the store has ever accumulated.
    @ObservationIgnored var loadedMessageIds = Set<Int64>()
    @ObservationIgnored var renderStore = MessageRenderStore()
    @ObservationIgnored let messageRenderLimiter = MessageRenderLimiter(limit: 8)
    @ObservationIgnored var audioPlaylist = [Audio]()
    @ObservationIgnored var displayedMessagesRebuildTask: Task<Void, Never>?
    @ObservationIgnored var pendingScrollMessageIds = Set<Int64>()
    @ObservationIgnored var pendingNavigationMessageId: Int64?
    @ObservationIgnored var pendingNavigationMovesAccessibilityFocus = false
    @ObservationIgnored var pendingViewedMessageIds = Set<Int64>()
    @ObservationIgnored var viewMessagesTask: Task<Void, Never>?
    @ObservationIgnored var conversationStatusTask: Task<Void, Never>?
    @ObservationIgnored var conversationPreparationTask: Task<Void, Never>?
    @ObservationIgnored var conversationPrepared = false
    /// One-shot timer that downgrades a stale "Online" once `UserStatusOnline.expires` passes
    /// without a fresh `updateUserStatus` from the server. See `applyUserPresence(_:)`.
    @ObservationIgnored var presenceExpiryTask: Task<Void, Never>?
    @ObservationIgnored var pinnedMessagesTask: Task<Void, Never>?
    @ObservationIgnored var pinnedMessagesGeneration = 0
    @ObservationIgnored var scheduledMessagesTask: Task<Void, Never>?
    @ObservationIgnored var scheduledMessagesGeneration = 0
    @ObservationIgnored var videoChatRefreshTask: Task<Void, Never>?
    /// Bumped every time a new history-loading task starts, so a superseded task's completion
    /// can tell it's stale and avoid clobbering `loadingMessagesTask`/`pendingNavigationMessageId`
    /// out from under a newer one (cancellation doesn't stop a network call already in flight).
    @ObservationIgnored var loadingMessagesGeneration = 0
    @ObservationIgnored var preparingVoiceNoteFileIds = Set<Int>()
    @ObservationIgnored var openedViewOnceVoiceNoteMessageIds = Set<Int64>()
    @ObservationIgnored var openingViewOnceVoiceNoteMessageIds = Set<Int64>()
    // Scroll
    @ObservationIgnored var isAtBottom = true
    var showScrollToBottomButton = false
    @ObservationIgnored weak var historyNavigator: ChatHistoryNavigator?
    @ObservationIgnored var cancellables = Set<AnyCancellable>()

    /// `onlineStatus` plus a ", N online" suffix for groups. Used for the conversation header and
    /// chat-info subtitle.
    ///
    /// Every input is read into a local *before* branching: this is a computed property on an
    /// `@Observable`, and SwiftUI only tracks the properties actually read during a body pass -
    /// a short-circuiting `guard` would drop `onlineMemberCount` (or `customChat.type`) as a
    /// dependency and the status would stop updating live.
    var conversationStatus: String {
        let base = onlineStatus
        let online = onlineMemberCount
        let isGroup = isGroupChat
        guard isGroup, online > 0, !base.isEmpty else { return base }
        return "\(base), \(online.formatted()) online"
    }

    var isGroupChat: Bool {
        switch customChat.type {
        case .group: true
        case .supergroup(let supergroup): !supergroup.isChannel
        case .bot, .user: false
        }
    }

    /// Telegram has no separate "Join Group" step for channel comments - sending your first
    /// comment on a post silently adds you to the channel's linked discussion group server-side,
    /// unlike opening an ordinary group/channel, which does require an explicit join before
    /// posting. Lets `ChatView` show the normal composer here even while `customChat.canJoin`.
    var isCommentThread: Bool {
        if case .messageTopicThread = messageTopic {
            true
        } else {
            false
        }
    }

    /// Opens the chat and kicks off history loading. `ChatView` is a SwiftUI value type that gets
    /// reconstructed (and this `ChatVM` re-initialized) on every unrelated body re-evaluation of its
    /// parent, so opening the chat and fetching history must not happen in `init` - only when the
    /// view genuinely appears, exactly once, via `.task`.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        let chatId = customChat.chat.id
        isChatTranslationEnabled = TelegramChatTranslationPreferences.isEnabled(chatId: chatId)
        setPublishers()
        startVideoChatObservation()
        refreshConversationStatus()
        refreshPinnedMessages()
        loadInitialMessages()
        loadThreadRootMessageIfNeeded()

        Task.main {
            guard let draftMessage = self.customChat.draftMessage else { return }
            let replyMessage = await self.getInputReplyToMessage(draftMessage.replyTo)
            withAnimation { self.composer.replyMessage = replyMessage }
        }
    }

    func refreshConversationStatus() {
        conversationStatusTask?.cancel()
        let type = customChat.type
        conversationStatusTask = Task { [weak self] in
            guard let self else { return }

            // 1:1 presence isn't fetched anywhere else - `init` only captured whatever
            // `customChat.user.status` was when the chat list last built this value, which can be
            // minutes stale by the time the chat is opened. Pull it fresh, then let live
            // `updateUserStatus` snapshots take over.
            if case .user(let user) = type {
                if let fresh = try? await service.getUser(userId: user.id), !Task.isCancelled {
                    applyUserPresence(fresh.status)
                }
                return
            }

            let status: String? =
                switch type {
                case .group(let currentGroup):
                    if let group = try? await service.getBasicGroup(basicGroupId: currentGroup.id) {
                        if group.memberCount > 0 {
                            conversationGroupStatus(memberCount: group.memberCount)
                        } else if let fullInfo = try? await service.getBasicGroupFullInfo(basicGroupId: group.id) {
                            conversationGroupStatus(memberCount: fullInfo.members.count)
                        } else {
                            "Group"
                        }
                    } else {
                        nil
                    }
                case .supergroup(let currentGroup):
                    if let group = try? await service.getSupergroup(supergroupId: currentGroup.id) {
                        if group.memberCount > 0 {
                            conversationSupergroupStatus(isChannel: group.isChannel, memberCount: group.memberCount)
                        } else if let fullInfo = try? await service.getSupergroupFullInfo(supergroupId: group.id) {
                            conversationSupergroupStatus(
                                isChannel: group.isChannel,
                                memberCount: fullInfo.memberCount,
                            )
                        } else {
                            group.isChannel ? "Channel" : "Group"
                        }
                    } else {
                        nil
                    }
                case .bot, .user:
                    nil
                }

            guard !Task.isCancelled, let status else { return }
            withAnimation { self.onlineStatus = status }
        }
    }

    func getOnlineStatus(from userStatus: UserStatus) -> String {
        telegramUserPresenceDescription(userStatus)
    }

    /// Renders `status` for a 1:1 chat and, while the peer is inside their online window, arms a
    /// single one-shot timer that recomputes the label the instant that window lapses.
    ///
    /// TDLib normally sends `.userStatusOffline` when the peer leaves, but that update is routinely
    /// missed (app backgrounded, socket drop), which otherwise leaves a permanently stuck "Online".
    /// `telegramUserPresenceDescription` is already wall-clock aware - past `expires` it renders
    /// `.userStatusOnline` as a "last seen" line - so recomputing from the *same* status once the
    /// deadline passes is enough; no fabricated status, no polling. Mirrors Unigram's
    /// `DialogViewModel.UpdateLastSeen` + `LastSeenConverter.OnlinePhraseChangeInSeconds`.
    func applyUserPresence(_ status: UserStatus) {
        presenceExpiryTask?.cancel()
        presenceExpiryTask = nil

        withAnimation { onlineStatus = getOnlineStatus(from: status) }

        guard let delay = telegramPresencePhraseChangeDelay(for: status) else { return }
        presenceExpiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            applyUserPresence(status)
        }
    }

    /// True when `messageTopic` is unset (ordinary full-chat mode) or `message` belongs to it -
    /// the single check every topic-scoping filter in `ChatVM+History.swift`/`ChatVM+Publishers.swift`
    /// funnels through, so there's one place that defines what "belongs to this thread" means.
    func messageMatchesTopic(_ message: Message) -> Bool {
        guard let messageTopic else { return true }
        if message.topicId == messageTopic {
            return true
        }
        // TDLib excludes a thread's own starting message (the channel post's copy in the
        // discussion group) from `getMessageThreadHistory` - it's fetched separately via
        // `getMessageThread`/`loadThreadRootMessageIfNeeded()` and merged into the store, but may
        // not carry a matching `topicId` the way replies do, so it needs this explicit id check.
        if case .messageTopicThread(let thread) = messageTopic, message.id == thread.messageThreadId {
            return true
        }
        return false
    }

    /// Joins the current channel/group and refreshes `customChat.type` with the resulting
    /// membership status - `CustomChat` isn't kept live against `updateSupergroup`/`updateBasicGroup`,
    /// so without this the "Join" button would keep showing until the chat is reopened.
    func joinCurrentChat() async {
        guard !isJoiningChat else { return }
        isJoiningChat = true
        defer { isJoiningChat = false }

        guard await (try? service.joinChat(chatId: chatId)) != nil else {
            navigationError = "Couldn't join this chat."
            return
        }

        switch customChat.type {
        case .supergroup(let currentGroup):
            guard let group = try? await service.getSupergroup(supergroupId: currentGroup.id) else { return }
            customChat.type = .supergroup(group)
        case .group(let currentGroup):
            guard let group = try? await service.getBasicGroup(basicGroupId: currentGroup.id) else { return }
            customChat.type = .group(group)
        case .bot, .user:
            break
        }
        refreshConversationStatus()
    }

    // MARK: Private

    @ObservationIgnored private var hasStarted = false
}
