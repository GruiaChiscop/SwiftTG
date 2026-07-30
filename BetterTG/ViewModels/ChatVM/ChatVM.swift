// ChatVM.swift

import AVKit
import Combine
import SwiftOGG
import SwiftUI
import TDLibKit
import UniformTypeIdentifiers

@Observable final class ChatVM {
    // MARK: Lifecycle

    init(
        customChat: CustomChat,
        initialMessageId: Int64? = nil,
        movesAccessibilityFocusToInitialMessage: Bool = false,
        service: any TelegramService = TDLib.shared.service,
    ) {
        self.customChat = customChat
        self.initialMessageId = initialMessageId
        self.movesAccessibilityFocusToInitialMessage = movesAccessibilityFocusToInitialMessage
        self.initialUnreadCount = customChat.unreadCount
        self.initialLastReadInboxMessageId = customChat.lastReadInboxMessageId
        self.service = service
        self.composer = MessageComposer(
            chatId: customChat.chat.id,
            service: service,
            draftMessage: customChat.draftMessage,
        )
        self.voiceRecorder = VoiceRecordingController(chatId: customChat.chat.id, service: service)
        if let user = customChat.user {
            self.onlineStatus = getOnlineStatus(from: user.status)
        } else {
            self.onlineStatus = conversationCommunityStatus(for: customChat)
        }
    }

    deinit {
        conversationStatusTask?.cancel()
        conversationSearchTask?.cancel()
        guard hasStarted else { return }
        let chatId = customChat.chat.id
        let service = service
        Task { _ = try? await service.closeChat(chatId: chatId) }
    }

    // MARK: Internal

    /// Opens the chat and kicks off history loading. `ChatView` is a SwiftUI value type that gets
    /// reconstructed (and this `ChatVM` re-initialized) on every unrelated body re-evaluation of its
    /// parent, so opening the chat and fetching history must not happen in `init` - only when the
    /// view genuinely appears, exactly once, via `.task`.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        let chatId = customChat.chat.id
        Task { _ = try? await service.openChat(chatId: chatId) }
        setPublishers()
        refreshConversationStatus()
        loadMessages()
        Media.shared.onChatOpen(title: customChat.chat.title)

        Task.background {
            guard let draftMessage = self.customChat.draftMessage else { return }
            let replyMessage = await self.getInputReplyToMessage(draftMessage.replyTo)
            withAnimation { self.composer.replyMessage = replyMessage }
        }
    }

    var customChat: CustomChat
    let initialMessageId: Int64?
    let movesAccessibilityFocusToInitialMessage: Bool
    let initialUnreadCount: Int
    let initialLastReadInboxMessageId: Int64

    let composer: MessageComposer
    let voiceRecorder: VoiceRecordingController

    var actionStatus = ""
    var onlineStatus = ""
    var highlightedMessageId: Int64?
    var scrollRequestMessageId: Int64?
    var accessibilityFocusRequestMessageId: Int64?
    var navigationError: String?
    var messagePendingForward: CustomMessage?
    var messages = [CustomMessage]()
    var initialMessagesLoaded = false
    var isConversationSearchActive = false
    var isSearchingConversation = false
    var conversationSearchQuery = ""
    var conversationSearchResultIds = [Int64]()
    var conversationSearchSelectedIndex: Int?
    var conversationSearchTotalCount = 0
    var conversationSearchError: String?
    @ObservationIgnored var dateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm"
        return dateFormatter
    }()

    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored var loadingMessagesTask: Task<Void, Never>?
    /// Bumped every time a new history-loading task starts, so a superseded task's completion
    /// can tell it's stale and avoid clobbering `loadingMessagesTask`/`pendingNavigationMessageId`
    /// out from under a newer one (cancellation doesn't stop a network call already in flight).
    @ObservationIgnored private var loadingMessagesGeneration = 0
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
    @ObservationIgnored var conversationSearchTask: Task<Void, Never>?
    @ObservationIgnored var conversationSearchGeneration = 0
    @ObservationIgnored var conversationSearchNextFromMessageId: Int64 = 0
    @ObservationIgnored var conversationSearchNextOffset = ""
    @ObservationIgnored var conversationSearchUsesSecretMessages = false
    // Scroll
    @ObservationIgnored var isAtBottom = true
    var showScrollToBottomButton = false
    @ObservationIgnored var scrollViewProxy: ScrollViewProxy?
    @ObservationIgnored var cancellables = Set<AnyCancellable>()
    @ObservationIgnored private var preparingVoiceNoteFileIds = Set<Int>()

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

    // MARK: Composer/Recorder facade

    var text: AttributedString {
        get { composer.text }
        set { composer.text = newValue }
    }

    var editMessageText: AttributedString {
        get { composer.editMessageText }
        set { composer.editMessageText = newValue }
    }

    var editCustomMessage: CustomMessage? {
        get { composer.editCustomMessage }
        set { composer.editCustomMessage = newValue }
    }

    var replyMessage: CustomMessage? {
        get { composer.replyMessage }
        set { composer.replyMessage = newValue }
    }

    var showSendButton: Bool {
        get { composer.showSendButton }
        set { composer.showSendButton = newValue }
    }

    var showDetail: Bool {
        get { composer.showDetail }
        set { composer.showDetail = newValue }
    }

    var displayedImages: [SelectedImage] {
        get { composer.displayedImages }
        set { composer.displayedImages = newValue }
    }

    var displayedDocuments: [URL] {
        get { composer.displayedDocuments }
        set { composer.displayedDocuments = newValue }
    }

    var showCameraView: Bool {
        get { composer.showCameraView }
        set { composer.showCameraView = newValue }
    }

    var showDocumentPicker: Bool {
        get { composer.showDocumentPicker }
        set { composer.showDocumentPicker = newValue }
    }

    var showPhotoPickerView: Bool {
        get { composer.showPhotoPickerView }
        set { composer.showPhotoPickerView = newValue }
    }

    var sendMessageTask: Task<Void, Never>? {
        get { composer.sendMessageTask }
        set { composer.sendMessageTask = newValue }
    }

    var errorShown: Bool {
        get { voiceRecorder.errorShown }
        set { voiceRecorder.errorShown = newValue }
    }

    var recordingVoiceNote: Bool {
        get { voiceRecorder.recordingVoiceNote }
        set { voiceRecorder.recordingVoiceNote = newValue }
    }

    var recordingLocked: Bool {
        get { voiceRecorder.recordingLocked }
        set { voiceRecorder.recordingLocked = newValue }
    }

    var recordingDragTranslation: CGSize {
        get { voiceRecorder.recordingDragTranslation }
        set { voiceRecorder.recordingDragTranslation = newValue }
    }

    var timerCount: Double {
        get { voiceRecorder.timerCount }
        set { voiceRecorder.timerCount = newValue }
    }

    var formattedTimerCount: String { voiceRecorder.formattedTimerCount }

    var wave: [Float] {
        get { voiceRecorder.wave }
        set { voiceRecorder.wave = newValue }
    }

    func sendMessage() async { await composer.sendMessage() }
    func stageDocuments(_ urls: [URL]) async { await composer.stageDocuments(urls) }
    func setShowSendButton() { composer.setShowSendButton() }
    func setEditMessageText(from message: Message?) { composer.setEditMessageText(from: message) }
    func updateDraft() async { await composer.updateDraft() }
    func startTimer() { voiceRecorder.startTimer() }
    func stopTimer() { voiceRecorder.stopTimer() }
    func mediaStartRecordingVoice() async { await voiceRecorder.mediaStartRecordingVoice() }
    func cancelRecordingVoice() { voiceRecorder.cancelRecordingVoice() }
    func mediaStopRecordingVoice(duration: Int, wave: [Float]) {
        guard let artifact = voiceRecorder.mediaStopRecordingVoice(duration: duration, wave: wave) else { return }
        Task.background {
            await self.composer.sendMessageVoiceNote(
                url: artifact.url,
                duration: artifact.duration,
                waveform: artifact.waveform,
            )
        }
    }

    // MARK: End facade

    /// Starts fetching the next batch once the user is getting close to the start of what's loaded,
    /// not only once they've hit it exactly - a VoiceOver swipe (or a fast scroll) that lands right on
    /// the edge would otherwise stall waiting on the network round trip before it has anything further
    /// to move to.
    static let loadMoreLookahead = 10

    func loadMoreIfNeeded(distanceFromStart: Int) {
        guard distanceFromStart <= Self.loadMoreLookahead else { return }
        loadMessages()
    }

    func updateBottomVisibility(isLastMessageVisible: Bool) {
        isAtBottom = isLastMessageVisible
        let shouldShowButton = !isLastMessageVisible
        guard showScrollToBottomButton != shouldShowButton else { return }
        withAnimation { showScrollToBottomButton = shouldShowButton }
    }
    
    func scrollToLast() {
        guard let lastId = messages.last?.id, let scrollViewProxy else { return }
        withAnimation { scrollViewProxy.scrollTo(lastId, anchor: .bottom) }
    }
    
    func scrollTo(id: Int64?, anchor: UnitPoint = .center) {
        guard let scrollViewProxy, let id else { return }
        
        withAnimation {
            scrollViewProxy.scrollTo(id, anchor: anchor)
            highlightedMessageId = id
        }
        
        Task.main(delay: 0.5) {
            withAnimation {
                self.highlightedMessageId = nil
            }
        }
    }

    func navigateToMessage(id: Int64, movesAccessibilityFocus: Bool = false) {
        if messages.contains(where: { $0.id == id }) {
            if movesAccessibilityFocus {
                accessibilityFocusRequestMessageId = id
            } else {
                scrollRequestMessageId = id
            }
            return
        }

        loadingMessagesTask?.cancel()
        loadingMessagesGeneration += 1
        let generation = loadingMessagesGeneration
        pendingNavigationMessageId = id
        pendingNavigationMovesAccessibilityFocus = movesAccessibilityFocus
        loadingMessagesTask = Task.background {
            guard let history = try? await self.service.getChatHistory(
                chatId: self.customChat.chat.id,
                fromMessageId: id,
                limit: 31,
                offset: -15,
                onlyLocal: false,
            ), !Task.isCancelled
            else {
                await main {
                    guard self.loadingMessagesGeneration == generation else { return }
                    self.pendingNavigationMessageId = nil
                    self.pendingNavigationMovesAccessibilityFocus = false
                    self.loadingMessagesTask = nil
                }
                return
            }
            let fetchedMessages = history.messages ?? []
            await main { self.loadedMessageIds.formUnion(fetchedMessages.map(\.id)) }
            self.service.mergeMessageHistory(
                chatId: self.customChat.chat.id,
                messages: fetchedMessages,
            )
            await main {
                guard self.loadingMessagesGeneration == generation else { return }
                self.loadingMessagesTask = nil
            }
        }
    }

    func navigateToRepliedMessage(from message: Message) {
        guard case .messageReplyToMessage(let reply) = message.replyTo,
              reply.messageId != 0
        else { return }
        let chatId = reply.chatId == 0 ? customChat.chat.id : reply.chatId
        guard chatId != customChat.chat.id else {
            navigateToMessage(id: reply.messageId, movesAccessibilityFocus: true)
            return
        }
        openChat(chatId: chatId, messageId: reply.messageId, movesAccessibilityFocus: true)
    }

    func navigateToForwardOrigin(from message: Message) {
        guard let origin = message.forwardInfo?.origin else { return }
        switch origin {
        case .messageOriginUser(let user):
            Task { @MainActor [weak self] in
                guard let chat = await RootVM.shared.getPrivateCustomChat(userId: user.senderUserId) else {
                    self?.navigationError = "This user can't be opened."
                    return
                }
                RootVM.shared.navigate(to: .customChat(chat, messageId: nil))
            }
        case .messageOriginChat(let chat):
            openChat(chatId: chat.senderChatId, messageId: nil)
        case .messageOriginChannel(let channel):
            openChat(chatId: channel.chatId, messageId: channel.messageId == 0 ? nil : channel.messageId)
        case .messageOriginHiddenUser:
            break
        }
    }

    func getOnlineStatus(from userStatus: UserStatus) -> String {
        telegramUserPresenceDescription(userStatus)
    }
    
    func loadMessages() {
        guard loadingMessagesTask == nil else { return }
        let fromMessageId = messages.first?.message.id ?? initialMessageId ?? 0
        loadingMessagesGeneration += 1
        let generation = loadingMessagesGeneration
        loadingMessagesTask = Task.background {
            await self._loadMessages(fromMessageId: fromMessageId, generation: generation)
        }
    }

    func _loadMessages(fromMessageId: Int64, generation: Int) async {
        guard let chatHistory = try? await service.getChatHistory(
            chatId: customChat.chat.id,
            fromMessageId: fromMessageId,
            limit: initialMessageId != nil && messages.isEmpty ? 31 : 30,
            offset: initialMessageId != nil && messages.isEmpty ? -15 : 0,
            onlyLocal: false,
        )
        .messages else {
            await main {
                guard self.loadingMessagesGeneration == generation else { return }
                self.loadingMessagesTask = nil
            }
            return
        }

        await main { self.loadedMessageIds.formUnion(chatHistory.map(\.id)) }
        service.mergeMessageHistory(chatId: customChat.chat.id, messages: chatHistory)
        await main {
            guard self.loadingMessagesGeneration == generation else { return }
            self.loadingMessagesTask = nil
        }
    }
    
    func deleteMessage(id: Int64, deleteForBoth: Bool) {
        guard let customMessage = messages.first(where: { $0.message.id == id }) else { return }
        let messageIds = customMessage.album.isEmpty ? [id] : customMessage.album.map(\.id)
        Task.background {
            try? await TelegramMessageActions.delete(
                service: self.service,
                chatId: self.customChat.chat.id,
                messageIds: messageIds,
                forEveryone: deleteForBoth,
            )
        }
    }

    func reply(to message: CustomMessage?) {
        if replyMessage != nil {
            withAnimation { replyMessage = nil }
            Task.main(delay: 0.4) {
                withAnimation { self.replyMessage = message }
            }
        } else {
            withAnimation { replyMessage = message }
        }
    }

    func edit(_ message: CustomMessage?) {
        if message != nil {
            displayedImages.removeAll()
            displayedDocuments.removeAll()
        }
        if editCustomMessage != nil {
            withAnimation { editCustomMessage = nil }
            Task.main(delay: 0.4) {
                withAnimation { self.editCustomMessage = message }
            }
        } else {
            withAnimation { editCustomMessage = message }
        }
    }

    func togglePinnedMessage(_ message: Message) {
        Task.background {
            try await TelegramMessageActions.togglePinned(service: self.service, message: message)
        }
    }

    func forward(_ message: CustomMessage) {
        messagePendingForward = message
    }

    @discardableResult func forwardMessage(_ message: CustomMessage, to chat: CustomChat) async -> Bool {
        let messageIds = message.album.isEmpty ? [message.id] : message.album.map(\.id)
        do {
            try await TelegramMessageActions.forward(
                service: service,
                messageIds: messageIds,
                fromChatId: customChat.chat.id,
                toChatId: chat.chat.id,
            )
            return true
        } catch {
            return false
        }
    }

    /// Forwards to every chat concurrently rather than one at a time, so picking several
    /// destinations doesn't make the last one wait on all the earlier round trips.
    @discardableResult func forwardMessage(_ message: CustomMessage, to chats: [CustomChat]) async -> Bool {
        let succeededCount = await withTaskGroup(of: Bool.self) { group in
            for chat in chats {
                group.addTask { await self.forwardMessage(message, to: chat) }
            }
            return await group.reduce(into: 0) { count, succeeded in count += succeeded ? 1 : 0 }
        }
        if succeededCount < chats.count {
            await main {
                self.navigationError = succeededCount == 0
                    ? "This message couldn't be forwarded."
                    : "The message couldn't be forwarded to all the selected chats."
            }
        }
        return succeededCount == chats.count
    }

    func toggleReaction(_ reaction: ReactionType, on message: Message) {
        Task.background {
            try? await TelegramMessageActions.toggleReaction(
                service: self.service,
                message: message,
                reaction: reaction,
            )
        }
    }

    /// Plays a voice note, downloading it first if `knownLocalPath` isn't already resolved.
    /// Returns the local path once playback starts, so the caller can cache it - or `nil` if a
    /// download for this file is already in flight or the download failed.
    @MainActor
    func toggleVoiceMessage(_ messageVoiceNote: MessageVoiceNote, knownLocalPath: String?) async -> String? {
        let fileId = messageVoiceNote.voiceNote.voice.id
        voicePlaybackTrace(
            "activation fileId=\(fileId) hasPath=\(knownLocalPath != nil) "
                + "preparing=\(preparingVoiceNoteFileIds.contains(fileId))",
        )
        if let knownLocalPath {
            startVoicePlayback(path: knownLocalPath, duration: messageVoiceNote.voiceNote.duration)
            return knownLocalPath
        }
        guard !preparingVoiceNoteFileIds.contains(fileId) else { return nil }
        preparingVoiceNoteFileIds.insert(fileId)
        defer { preparingVoiceNoteFileIds.remove(fileId) }
        TelegramAudioPlayer.shared.stop()
        do {
            let file = try await service.downloadFile(
                fileId: fileId,
                limit: 0,
                offset: 0,
                priority: 32,
                synchronous: true,
            )
            guard file.local.isDownloadingCompleted, !file.local.path.isEmpty else { return nil }
            voicePlaybackTrace("download completed fileId=\(file.id) size=\(file.local.downloadedSize)")
            startVoicePlayback(path: file.local.path, duration: messageVoiceNote.voiceNote.duration)
            return file.local.path
        } catch {
            voicePlaybackTrace("download failed: \(error.localizedDescription)")
            log("Failed to download voice message:", error)
            return nil
        }
    }

    @MainActor
    private func startVoicePlayback(path: String, duration: Int) {
        voicePlaybackTrace(
            "start requested exists=\(FileManager.default.fileExists(atPath: path)) duration=\(duration)",
        )
        TelegramAudioPlayer.shared.stop()
        Media.shared.toggle(with: path, duration: duration)
    }

    @MainActor
    func viewMessage(id: Int64) {
        pendingViewedMessageIds.insert(id)
        guard viewMessagesTask == nil else { return }

        viewMessagesTask = Task { @MainActor [weak self] in
            try? await Task<Never, Never>.sleep(for: .milliseconds(50))
            guard let self, !Task.isCancelled else { return }

            let messageIds = Array(pendingViewedMessageIds)
            pendingViewedMessageIds.removeAll(keepingCapacity: true)
            viewMessagesTask = nil
            guard !messageIds.isEmpty else { return }

            let chatId = customChat.chat.id
            let service = service
            Task.background {
                try? await service.viewMessages(
                    chatId: chatId,
                    forceRead: true,
                    messageIds: messageIds,
                    source: nil,
                )
            }
        }
    }
    
    func getCustomMessage(fromId id: Int64) async -> CustomMessage? {
        guard let message = try? await service.getMessage(chatId: customChat.chat.id, messageId: id) else { return nil }
        return await getCustomMessage(from: message)
    }
    
    func getCustomMessage(from message: Message) async -> CustomMessage {
        async let replyToMessageTask = getReplyToMessage(message.replyTo)
        async let forwardedFromTask = getForwardedFrom(message.forwardInfo?.origin)
        async let propertiesTask = service.getMessageProperties(
            chatId: customChat.chat.id, messageId: message.id,
        )
        async let reactionsTask = service.getMessageAvailableReactions(
            chatId: customChat.chat.id,
            messageId: message.id,
            rowSize: 8,
        )
        async let senderUserTask = resolvedSenderUser(for: message.senderId)
        async let serviceMessageTextTask = TelegramServiceMessage.description(service: service, message: message)

        let replyToMessage = await replyToMessageTask
        let customMessage = await CustomMessage(
            message: message,
            replyToMessage: replyToMessage,
            forwardedFrom: forwardedFromTask,
            properties: (try? propertiesTask) ?? .default,
        )
        customMessage.senderUser = await senderUserTask
        if case .messageSenderChat = message.senderId {
            customMessage.senderChatTitle = await TelegramSenderName.displayName(service: service, senderId: message.senderId)
        }
        customMessage.serviceMessageText = await serviceMessageTextTask
        if let reactions = try? await reactionsTask {
            customMessage.availableReactions = telegramAvailableReactions(reactions)
        }

        if message.mediaAlbumId != 0 {
            customMessage.album.append(message)
        }

        if case .messageSenderUser(let messageSenderUser) = replyToMessage?.senderId {
            customMessage.replyUser = try? await service.getUser(userId: messageSenderUser.userId)
            customMessage.replySenderName = customMessage.replyUser.map(telegramUserDisplayName)
        } else if case .messageSenderChat(let messageSenderChat) = replyToMessage?.senderId {
            customMessage.replySenderName = try? await service.getChat(chatId: messageSenderChat.chatId).title
        }
        
        if let serviceMessageText = customMessage.serviceMessageText {
            customMessage.formattedText = FormattedText(entities: [], text: serviceMessageText)
        } else {
            switch message.content {
            case .messageText(let messageText):
                customMessage.formattedText = messageText.text
            case .messagePhoto, .messageVideo, .messageDocument, .messageVoiceNote, .messageAudio:
                customMessage.formattedText = telegramMessageFormattedText(message)
            case .messageUnsupported:
                customMessage.formattedText = FormattedText(entities: [], text: "TDLib not supported")
            default:
                customMessage.formattedText = FormattedText(entities: [], text: "BTG not supported")
            }
        }
        
        return customMessage
    }

    func resolvedSenderUser(for senderId: MessageSender) async -> User? {
        guard case .messageSenderUser(let sender) = senderId else { return nil }
        return try? await service.getUser(userId: sender.userId)
    }

    func getForwardedFrom(_ origin: MessageOrigin?) async -> String? {
        guard let origin else { return nil }
        return await TelegramMessageOrigin.displayName(service: service, origin: origin)
    }
    
    func getReplyToMessage(_ replyTo: MessageReplyTo?) async -> Message? {
        if case .messageReplyToMessage(let messageReplyToMessage) = replyTo, messageReplyToMessage.messageId != 0 {
            return try? await service.getMessage(
                chatId: messageReplyToMessage.chatId == 0
                    ? customChat.chat.id
                    : messageReplyToMessage.chatId,
                messageId: messageReplyToMessage.messageId,
            )
        }
        return nil
    }
    
    func getInputReplyToMessage(_ inputMessageReplyTo: InputMessageReplyTo?) async -> CustomMessage? {
        if case .inputMessageReplyToMessage(let message) = inputMessageReplyTo {
            return await getCustomMessage(fromId: message.messageId)
        }
        return nil
    }
    
    // MARK: Private

    private func openChat(chatId: Int64, messageId: Int64?, movesAccessibilityFocus: Bool = false) {
        Task { @MainActor [weak self] in
            guard let chat = await RootVM.shared.getCustomChat(from: chatId) else {
                self?.navigationError = "This chat is private or unavailable."
                return
            }
            RootVM.shared.navigate(to: .customChat(
                chat,
                messageId: messageId,
                movesAccessibilityFocus: movesAccessibilityFocus,
            ))
        }
    }
}
