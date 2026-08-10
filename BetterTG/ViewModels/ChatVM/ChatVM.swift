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
        self.initialUnreadCount = customChat.unreadCount
        self.initialLastReadInboxMessageId = customChat.lastReadInboxMessageId
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
        self.conversationSearch = TelegramConversationSearchStore(service: service)
        self.favoriteStickers = TelegramFavoriteStickersStore(service: service)
        self.onlineStatus =
            if let user = customChat.user {
                getOnlineStatus(from: user.status)
            } else {
                conversationCommunityStatus(for: customChat)
            }
    }

    deinit {
        conversationStatusTask?.cancel()
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
    let initialUnreadCount: Int
    let initialLastReadInboxMessageId: Int64

    let composer: MessageComposer
    let voiceRecorder: VoiceRecordingController
    let conversationSearch: TelegramConversationSearchStore
    let favoriteStickers: TelegramFavoriteStickersStore

    var actionStatus = ""
    var isJoiningChat = false
    var onlineStatus = ""
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
    @ObservationIgnored var pinnedMessagesTask: Task<Void, Never>?
    @ObservationIgnored var pinnedMessagesGeneration = 0
    @ObservationIgnored var scheduledMessagesTask: Task<Void, Never>?
    @ObservationIgnored var scheduledMessagesGeneration = 0
    /// Bumped every time a new history-loading task starts, so a superseded task's completion
    /// can tell it's stale and avoid clobbering `loadingMessagesTask`/`pendingNavigationMessageId`
    /// out from under a newer one (cancellation doesn't stop a network call already in flight).
    @ObservationIgnored var loadingMessagesGeneration = 0
    @ObservationIgnored var preparingVoiceNoteFileIds = Set<Int>()
    // Scroll
    @ObservationIgnored var isAtBottom = true
    var showScrollToBottomButton = false
    @ObservationIgnored var scrollViewProxy: ScrollViewProxy?
    @ObservationIgnored var cancellables = Set<AnyCancellable>()

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
        Task { _ = try? await service.openChat(chatId: chatId) }
        setPublishers()
        refreshConversationStatus()
        refreshPinnedMessages()
        loadMessages()
        loadThreadRootMessageIfNeeded()
        Media.shared.onChatOpen(title: customChat.chat.title)

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
