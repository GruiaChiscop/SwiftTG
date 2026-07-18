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
        service: any TelegramService = TDLib.shared.service,
    ) {
        self.customChat = customChat
        self.initialMessageId = initialMessageId
        self.initialUnreadCount = customChat.unreadCount
        self.initialLastReadInboxMessageId = customChat.lastReadInboxMessageId
        self.service = service
        if let user = customChat.user {
            self.onlineStatus = getOnlineStatus(from: user.status)
        }

        if let draftMessage = customChat.draftMessage,
           case .draftMessageContentText(let draftMessageContentText) = draftMessage.content
        {
            self.text = getAttributedString(from: draftMessageContentText.text)
        }
    }

    deinit {
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
        loadMessages()
        Media.shared.onChatOpen(title: customChat.chat.title)

        Task.background {
            guard let draftMessage = self.customChat.draftMessage else { return }
            let replyMessage = await self.getInputReplyToMessage(draftMessage.replyTo)
            withAnimation { self.replyMessage = replyMessage }
        }
    }

    var customChat: CustomChat
    let initialMessageId: Int64?
    let initialUnreadCount: Int
    let initialLastReadInboxMessageId: Int64

    var bottomAreaHeight = CGFloat.zero
    var actionStatus = ""
    var onlineStatus = ""
    var editCustomMessage: CustomMessage?
    var replyMessage: CustomMessage?
    var highlightedMessageId: Int64?
    var accessibilityFocusRequestMessageId: Int64?
    var navigationError: String?
    var messages = [CustomMessage]()
    var initialMessagesLoaded = false
    @ObservationIgnored var dateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm"
        return dateFormatter
    }()

    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored var loadingMessagesTask: Task<Void, Never>?
    @ObservationIgnored let service: any TelegramService
    @ObservationIgnored var appliedMessageSnapshotVersion: UInt64?
    @ObservationIgnored var latestMessageSnapshot: TelegramMessageSnapshot?
    @ObservationIgnored var renderedMessages = [Int64: CustomMessage]()
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
    @ObservationIgnored var pendingViewedMessageIds = Set<Int64>()
    @ObservationIgnored var viewMessagesTask: Task<Void, Never>?
    // Scroll
    @ObservationIgnored var scrollOnFocus = true
    var showScrollToBottomButton = false
    @ObservationIgnored var scrollViewProxy: ScrollViewProxy?
    @ObservationIgnored var cancellables = Set<AnyCancellable>()
    var displayedImages = [SelectedImage]()
    var displayedDocuments = [URL]()
    var timerCount = 0.0
    @ObservationIgnored var timer: Timer?
    @ObservationIgnored var wave = [Float]()
    @ObservationIgnored var sendMessageTask: Task<Void, Never>?
    @ObservationIgnored var setDisplayedImagesTask: Task<Void, Never>?
    var showDetail = false
    var showSendButton = false
    var text: AttributedString = ""
    var editMessageText: AttributedString = ""
    var recordingVoiceNote = false
    var recordingLocked = false
    var recordingDragTranslation = CGSize.zero
    var errorShown = false
    var showCameraView = false
    var showDocumentPicker = false
    var showPhotoPickerView = false
    @ObservationIgnored var savedVoiceNoteUrl = URL(filePath: "")
    @ObservationIgnored var audioRecorder: VoiceNoteRecorder?
    
    var canEditMessage: Bool {
        guard let editCustomMessage else { return false }
        switch editCustomMessage.message.content {
        case .messageAudio, .messageDocument, .messagePhoto, .messageVideo, .messageVoiceNote:
            return true
        case .messageText:
            return !editMessageText.characters.isEmpty
        default:
            return false
        }
    }
    
    var formattedTimerCount: String {
        let time = String(format: "%.2f", timerCount).split(separator: ".", maxSplits: 2)
        let seconds = Int(time[0]) ?? 0
        var resultString = ""
        if seconds >= 60 {
            resultString += "\(seconds / 60):" // seconds / 60 == minutes
            var estimatedSeconds = String(seconds % 60)
            if estimatedSeconds.count == 1 {
                estimatedSeconds = "0\(estimatedSeconds)"
            }
            resultString += "\(estimatedSeconds)"
        } else {
            resultString += "\(seconds).\(time[1])" // time[1] == millisecongs
        }
        return resultString
    }
    
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
        scrollOnFocus = isLastMessageVisible
        let shouldShowButton = !isLastMessageVisible
        guard showScrollToBottomButton != shouldShowButton else { return }
        withAnimation { showScrollToBottomButton = shouldShowButton }
    }
    
    func getLastSeenTime(_ time: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(time))
        let dateFormatter = DateFormatter()
        
        let difference = Date().timeIntervalSince1970 - TimeInterval(time)
        if difference < 60 {
            return "now"
        } else if difference < 60 * 60 {
            return "\(Int(difference / 60)) minutes ago"
        } else if difference < 60 * 60 * 24 {
            return "\(Int(difference / 60 / 60)) hours ago"
        } else if difference < 60 * 60 * 24 * 2 {
            dateFormatter.dateFormat = "HH:mm"
            return "yesterday at \(dateFormatter.string(from: date))"
        } else {
            dateFormatter.dateFormat = "dd.MM.yy"
            return dateFormatter.string(from: date)
        }
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

    func navigateToMessage(id: Int64) {
        if messages.contains(where: { $0.id == id }) {
            accessibilityFocusRequestMessageId = id
            return
        }

        loadingMessagesTask?.cancel()
        pendingNavigationMessageId = id
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
                    self.pendingNavigationMessageId = nil
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
            navigateToMessage(id: reply.messageId)
            return
        }
        openChat(chatId: chatId, messageId: reply.messageId)
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
        switch userStatus {
        case .userStatusEmpty: "empty"
        case .userStatusOnline: /* (let userStatusOnline) */ "online"
        case .userStatusOffline(let userStatusOffline): "last seen \(getLastSeenTime(userStatusOffline.wasOnline))"
        case .userStatusRecently: "last seen recently"
        case .userStatusLastWeek: "last seen last week"
        case .userStatusLastMonth: "last seen last month"
        }
    }
    
    func loadMessages() {
        guard loadingMessagesTask == nil else { return }
        let fromMessageId = messages.first?.message.id ?? initialMessageId ?? 0
        loadingMessagesTask = Task.background {
            await self._loadMessages(fromMessageId: fromMessageId)
        }
    }
    
    func _loadMessages(fromMessageId: Int64) async {
        guard let chatHistory = try? await service.getChatHistory(
            chatId: customChat.chat.id,
            fromMessageId: fromMessageId,
            limit: initialMessageId != nil && messages.isEmpty ? 31 : 30,
            offset: initialMessageId != nil && messages.isEmpty ? -15 : 0,
            onlyLocal: false,
        )
        .messages else {
            await main { self.loadingMessagesTask = nil }
            return
        }

        await main { self.loadedMessageIds.formUnion(chatHistory.map(\.id)) }
        service.mergeMessageHistory(chatId: customChat.chat.id, messages: chatHistory)
        await main { self.loadingMessagesTask = nil }
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
            case .messagePhoto(let messagePhoto):
                if !messagePhoto.caption.text.isEmpty {
                    customMessage.formattedText = messagePhoto.caption
                }
            case .messageVideo(let messageVideo):
                if !messageVideo.caption.text.isEmpty {
                    customMessage.formattedText = messageVideo.caption
                }
            case .messageDocument(let messageDocument):
                if !messageDocument.caption.text.isEmpty {
                    customMessage.formattedText = messageDocument.caption
                }
            case .messageVoiceNote(let messageVoiceNote):
                if !messageVoiceNote.caption.text.isEmpty {
                    customMessage.formattedText = messageVoiceNote.caption
                }
            case .messageAudio(let messageAudio):
                if !messageAudio.caption.text.isEmpty {
                    customMessage.formattedText = messageAudio.caption
                }
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
    
    func sendMessageVoiceNote(duration: Int, waveform: Data) async {
        try? await TelegramVoiceNoteSending.send(
            service: service,
            chatId: customChat.chat.id,
            url: savedVoiceNoteUrl,
            caption: FormattedText(
                entities: getEntities(from: text),
                text: text.string,
            ),
            duration: duration,
            waveform: waveform,
            replyTo: getMessageReplyTo(from: replyMessage),
        )
        text = ""
    }
    
    func sendMessage() async {
        if !displayedDocuments.isEmpty {
            await sendMessageDocuments()
        } else if !displayedImages.isEmpty {
            await sendMessagePhotos()
        } else if canEditMessage {
            await editMessage()
        } else if !text.characters.isEmpty {
            await sendMessageText()
        } else {
            return
        }
        
        await main {
            withAnimation {
                self.displayedImages.removeAll()
                self.displayedDocuments.removeAll()
                self.editMessageText = ""
                self.text = ""
                self.replyMessage = nil
                self.editCustomMessage = nil
            }
        }
    }

    func stageDocuments(_ urls: [URL]) async {
        let stagedURLs = await stageAttachmentURLs(urls)
        displayedImages.removeAll()
        displayedDocuments = stagedURLs
        setShowSendButton()
    }

    func stagePastedAttachments(_ urls: [URL]) async {
        let stagedURLs = await stageAttachmentURLs(urls)
        guard !stagedURLs.isEmpty else { return }
        var seenURLs = Set<URL>()
        let combined = (displayedImages.map(\.url) + displayedDocuments + stagedURLs).filter {
            seenURLs.insert($0).inserted
        }
        let containsOnlyImages = combined.allSatisfy { url in
            let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
            guard let type = type ?? UTType(filenameExtension: url.pathExtension) else { return false }
            return type.conforms(to: .image)
        }
        if containsOnlyImages {
            displayedDocuments.removeAll()
            displayedImages = combined.compactMap { url in
                guard let preview = downsampledImage(at: url, maxPixelSize: 320) else { return nil }
                return SelectedImage(image: Image(uiImage: preview), url: url)
            }
        } else {
            displayedImages.removeAll()
            displayedDocuments = combined
        }
        setShowSendButton()
    }

    private func stageAttachmentURLs(_ urls: [URL]) async -> [URL] {
        await Task.detached(priority: .userInitiated) {
            urls.compactMap { source -> URL? in
                let accessed = source.startAccessingSecurityScopedResource()
                defer {
                    if accessed {
                        source.stopAccessingSecurityScopedResource()
                    }
                }
                let destination = URL(filePath: NSTemporaryDirectory())
                    .appending(path: "\(UUID().uuidString)-\(source.lastPathComponent)")
                do {
                    try FileManager.default.copyItem(at: source, to: destination)
                    return destination
                } catch {
                    return nil
                }
            }
        }.value
    }

    func sendMessageDocuments() async {
        let caption = await TelegramTextFormatting.addingAutomaticEntities(
            service: service,
            to: FormattedText(entities: getEntities(from: text), text: text.string),
        )
        let contents = displayedDocuments.map { url in
            TelegramMessageSending.documentContent(url: url, caption: caption)
        }
        _ = try? await TelegramMessageSending.send(
            service: service,
            chatId: customChat.chat.id,
            contents: contents,
            replyTo: getMessageReplyTo(from: replyMessage),
            uploadAction: .chatActionUploadingDocument(.init(progress: 0)),
        )
    }
    
    func sendMessagePhotos() async {
        let caption = await TelegramTextFormatting.addingAutomaticEntities(
            service: service,
            to: FormattedText(entities: getEntities(from: text), text: text.string),
        )
        let contents = displayedImages.map { makeInputMessageContent(for: $0.url, caption: caption) }
        _ = try? await TelegramMessageSending.send(
            service: service,
            chatId: customChat.chat.id,
            contents: contents,
            replyTo: getMessageReplyTo(from: replyMessage),
            uploadAction: .chatActionUploadingPhoto(.init(progress: 0)),
        )
    }
    
    func makeInputMessageContent(for url: URL, caption: FormattedText) -> InputMessageContent {
        let pixelSize = imagePixelSize(at: url) ?? .zero
        return TelegramMessageSending.photoContent(
            url: url,
            caption: caption,
            width: Int(pixelSize.width),
            height: Int(pixelSize.height),
        )
    }
    
    func sendMessageText() async {
        let formattedText = await TelegramTextFormatting.addingAutomaticEntities(
            service: service,
            to: FormattedText(entities: getEntities(from: text), text: text.string),
        )
        let content = TelegramMessageSending.textContent(formattedText)
        _ = try? await TelegramMessageSending.send(
            service: service,
            chatId: customChat.chat.id,
            contents: [content],
            replyTo: getMessageReplyTo(from: replyMessage),
        )
    }
    
    func editMessage() async {
        guard let message = editCustomMessage?.message else { return }
        let newText = FormattedText(entities: getEntities(from: editMessageText), text: editMessageText.string)
        let supported = await TelegramMessageEditing.editMessage(
            service: service,
            chatId: customChat.chat.id,
            messageId: message.id,
            messageContent: message.content,
            newText: newText,
        )
        if !supported {
            log("Unsupported edit message type")
        }
    }
    
    func updateDraft() async {
        let draftMessage = DraftMessage(
            content: .draftMessageContentText(
                DraftMessageContentText(
                    linkPreviewOptions: nil,
                    text: FormattedText(
                        entities: getEntities(from: text),
                        text: text.string,
                    ),
                ),
            ),
            date: Int(Date.now.timeIntervalSince1970),
            effectId: 0,
            replyTo: getMessageReplyTo(from: replyMessage),
            suggestedPostInfo: nil,
        )
        _ = try? await service.setChatDraftMessage(
            chatId: customChat.chat.id,
            draftMessage: draftMessage,
            topicId: nil,
        )
    }
    
    func setShowSendButton() {
        guard editCustomMessage == nil else { return withAnimation { showSendButton = true } }
        let value = !displayedDocuments.isEmpty || !displayedImages.isEmpty
            || !editMessageText.characters.isEmpty || !text.characters.isEmpty
        withAnimation { showSendButton = value }
    }
    
    func setEditMessageText(from message: Message?) {
        withAnimation {
            guard let message, let formattedText = TelegramMessageEditing.editableFormattedText(from: message)
            else { return }
            editMessageText = getAttributedString(from: formattedText)
        }
    }
    
    func getMessageReplyTo(from customMessage: CustomMessage?) -> InputMessageReplyTo? {
        TelegramMessageSending.replyTo(messageId: customMessage?.message.id)
    }
    
    func startTimer() {
        let timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self] timer in
            guard let self, let audioRecorder else { return }
            wave.append(audioRecorder.peakPower)
            timerCount += timer.timeInterval
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    
    func stopTimer() {
        timer?.invalidate()
        timer = nil
        timerCount = 0
    }
    
    func tdSendChatAction(_ chatAction: ChatAction) async throws {
        _ = try await service.sendChatAction(
            action: chatAction,
            businessConnectionId: nil,
            chatId: customChat.chat.id,
            topicId: nil,
        )
    }
    
    @MainActor func mediaStartRecordingVoice() async {
        Media.shared.setAudioSessionRecord()
        Media.shared.stop()
        
        let granted = await AVAudioApplication.requestRecordPermission()
        if granted {
            log("Access to Microphone for Voice messages is granted")
        } else {
            log("Access to Microphone for Voice messages is not granted")
            errorShown = true
            return
        }
        
        let url = TelegramVoiceNoteSending.temporaryFileURL()
        savedVoiceNoteUrl = url

        do {
            let recorder = VoiceNoteRecorder()
            try recorder.start()
            audioRecorder = recorder
            withAnimation {
                recordingVoiceNote = true
                recordingLocked = false
                recordingDragTranslation = .zero
            }
            try? await tdSendChatAction(.chatActionRecordingVoiceNote)
        } catch {
            log("Error creating AudioRecorder: \(error)")
        }
    }

    func cancelRecordingVoice() {
        audioRecorder?.cancel()
        audioRecorder = nil
        TelegramVoiceNoteStaging.shared.discard(fileURL: savedVoiceNoteUrl)
        withAnimation {
            recordingVoiceNote = false
            recordingLocked = false
            recordingDragTranslation = .zero
        }
        Task.background { try? await self.tdSendChatAction(.chatActionCancel) }
    }

    func mediaStopRecordingVoice(duration: Int, wave: [Float]) {
        guard let audioRecorder else { return }
        let encodedDuration: Int
        do {
            encodedDuration = try Int(ceil(audioRecorder.stopAndWrite(to: savedVoiceNoteUrl)))
        } catch {
            log("Error finalizing voice note:", error)
            cancelRecordingVoice()
            return
        }
        self.audioRecorder = nil
        withAnimation {
            recordingVoiceNote = false
            recordingLocked = false
            recordingDragTranslation = .zero
        }
        Task.background { try? await self.tdSendChatAction(.chatActionCancel) }

        let waveform = TelegramVoiceNoteSending.waveform(from: wave)
        Task.background {
            await self.sendMessageVoiceNote(duration: max(encodedDuration, duration), waveform: waveform)
        }
    }

    // MARK: Private

    private func openChat(chatId: Int64, messageId: Int64?) {
        Task { @MainActor [weak self] in
            guard let chat = await RootVM.shared.getCustomChat(from: chatId) else {
                self?.navigationError = "This chat is private or unavailable."
                return
            }
            RootVM.shared.navigate(to: .customChat(chat, messageId: messageId))
        }
    }
}
