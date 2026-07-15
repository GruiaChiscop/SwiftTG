// ChatVM.swift

import AVKit
import Combine
import SwiftOGG
import SwiftUI
import TDLibKit

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
        log("init \(customChat.chat.id)")
        if let user = customChat.user {
            self.onlineStatus = getOnlineStatus(from: user.status)
        }
        
        Task { _ = try? await service.openChat(chatId: customChat.chat.id) }
        setPublishers()
        loadMessages()
        Media.shared.onChatOpen(title: customChat.chat.title)
        
        if let draftMessage = customChat.draftMessage,
           case .draftMessageContentText(let draftMessageContentText) = draftMessage.content
        {
            self.text = getAttributedString(from: draftMessageContentText.text)
        }
        
        Task.background {
            guard let draftMessage = customChat.draftMessage else { return }
            let replyMessage = await self.getInputReplyToMessage(draftMessage.replyTo)
            withAnimation { self.replyMessage = replyMessage }
        }
    }
    
    deinit {
        log("deinit \(customChat.chat.id)")
        let chatId = customChat.chat.id
        let service = service
        Task { _ = try? await service.closeChat(chatId: chatId) }
        Media.shared.onChatDismiss()
    }
    
    // MARK: Internal

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

    @ObservationIgnored var loadingMessagesTask: Task<Void, Never>?
    @ObservationIgnored let service: any TelegramService
    @ObservationIgnored var appliedMessageSnapshotVersion: UInt64?
    @ObservationIgnored var latestMessageSnapshot: TelegramMessageSnapshot?
    @ObservationIgnored var renderedMessages = [Int64: CustomMessage]()
    @ObservationIgnored var renderedInvalidationVersions = [Int64: UInt64]()
    @ObservationIgnored var renderingMessages = [Int64: Message]()
    @ObservationIgnored var renderingInvalidationVersions = [Int64: UInt64]()
    @ObservationIgnored var renderGenerations = [Int64: UInt64]()
    @ObservationIgnored var messageInvalidationVersions = [Int64: UInt64]()
    @ObservationIgnored var refreshVersions = [Int64: UInt64]()
    @ObservationIgnored var refreshedMessagesAwaitingMerge = [Int64: Message]()
    @ObservationIgnored var pendingScrollMessageIds = Set<Int64>()
    @ObservationIgnored var pendingNavigationMessageId: Int64?
    @ObservationIgnored var nextRenderGeneration: UInt64 = 0
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
        case .messageDocument, .messagePhoto, .messageVideo, .messageVoiceNote:
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
    
    func loadMoreIfNeeded(for customMessage: CustomMessage) {
        guard customMessage.id == messages.first?.id else { return }
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
            self.service.mergeMessageHistory(
                chatId: self.customChat.chat.id,
                messages: history.messages ?? [],
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
                NavigationStorage.shared.push(.customChat(chat, messageId: nil))
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

        service.mergeMessageHistory(chatId: customChat.chat.id, messages: chatHistory)
        await main { self.loadingMessagesTask = nil }
    }
    
    func deleteMessage(id: Int64, deleteForBoth: Bool) {
        guard let customMessage = messages.first(where: { $0.message.id == id }) else { return }
        Task.background {
            if customMessage.album.isEmpty {
                _ = try? await self.service.deleteMessages(
                    chatId: self.customChat.chat.id,
                    messageIds: [id],
                    revoke: deleteForBoth,
                )
            } else {
                let ids = customMessage.album.map(\.id)
                _ = try? await self.service.deleteMessages(
                    chatId: self.customChat.chat.id,
                    messageIds: ids,
                    revoke: deleteForBoth,
                )
            }
        }
    }
    
    func viewMessage(id: Int64) {
        Task.background {
            try await self.service.viewMessages(
                chatId: self.customChat.chat.id,
                forceRead: true,
                messageIds: [id],
                source: nil,
            )
        }
    }
    
    func getCustomMessage(fromId id: Int64) async -> CustomMessage? {
        guard let message = try? await service.getMessage(chatId: customChat.chat.id, messageId: id) else { return nil }
        return await getCustomMessage(from: message)
    }
    
    func getCustomMessage(from message: Message) async -> CustomMessage {
        let replyToMessage = await getReplyToMessage(message.replyTo)
        let customMessage = await CustomMessage(
            message: message,
            replyToMessage: replyToMessage,
            forwardedFrom: getForwardedFrom(message.forwardInfo?.origin),
            properties: (try? service.getMessageProperties(
                chatId: customChat.chat.id, messageId: message.id,
            )) ?? .default,
        )
        if let reactions = try? await service.getMessageAvailableReactions(
            chatId: customChat.chat.id,
            messageId: message.id,
            rowSize: 8,
        ) {
            customMessage.canReact = reactions.unavailabilityReason == nil
                && (reactions.topReactions + reactions.recentReactions + reactions.popularReactions).contains {
                    $0.type == .reactionTypeEmoji(.init(emoji: "❤"))
                }
        }
        
        if message.mediaAlbumId != 0 {
            customMessage.album.append(message)
        }
        
        if case .messageSenderUser(let messageSenderUser) = message.senderId {
            customMessage.senderUser = try? await service.getUser(userId: messageSenderUser.userId)
        }
        
        if case .messageSenderUser(let messageSenderUser) = replyToMessage?.senderId {
            customMessage.replyUser = try? await service.getUser(userId: messageSenderUser.userId)
            customMessage.replySenderName = customMessage.replyUser.map {
                "\($0.firstName) \($0.lastName)".trimmingCharacters(in: .whitespaces)
            }
        } else if case .messageSenderChat(let messageSenderChat) = replyToMessage?.senderId {
            customMessage.replySenderName = try? await service.getChat(chatId: messageSenderChat.chatId).title
        }
        
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
        case .messageUnsupported:
            customMessage.formattedText = FormattedText(entities: [], text: "TDLib not supported")
        default:
            customMessage.formattedText = FormattedText(entities: [], text: "BTG not supported")
        }
        
        return customMessage
    }
    
    func getForwardedFrom(_ origin: MessageOrigin?) async -> String? {
        guard let origin else { return nil }
        
        switch origin {
        case .messageOriginChat(let chat):
            if let title = await (try? service.getChat(chatId: chat.senderChatId))?.title {
                return !chat.authorSignature.isEmpty ? "\(title) (\(chat.authorSignature))" : title
            } else {
                return !chat.authorSignature.isEmpty ? chat.authorSignature : nil
            }
        case .messageOriginChannel(let channel):
            if let title = await (try? service.getChat(chatId: channel.chatId))?.title {
                return !channel.authorSignature.isEmpty ? "\(title) (\(channel.authorSignature))" : title
            } else {
                return !channel.authorSignature.isEmpty ? channel.authorSignature : nil
            }
        case .messageOriginHiddenUser(let messageOriginHiddenUser):
            return messageOriginHiddenUser.senderName
        case .messageOriginUser(let messageOriginUser):
            return await (try? service.getUser(userId: messageOriginUser.senderUserId))?.firstName
        }
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
        _ = try? await service.sendMessage(
            chatId: customChat.chat.id,
            inputMessageContent: .inputMessageVoiceNote(
                .init(
                    caption: FormattedText(
                        entities: getEntities(from: text),
                        text: text.string,
                    ),
                    duration: duration,
                    selfDestructType: nil,
                    voiceNote: .inputFileLocal(.init(path: savedVoiceNoteUrl.path())),
                    waveform: waveform,
                ),
            ),
            options: nil,
            replyMarkup: nil,
            replyTo: getMessageReplyTo(from: replyMessage),
            topicId: nil,
        )
        text = ""
        try? await tdSendChatAction(.chatActionCancel)
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
        let stagedURLs = await Task.detached(priority: .userInitiated) {
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
        displayedImages.removeAll()
        displayedDocuments = stagedURLs
        setShowSendButton()
    }

    func sendMessageDocuments() async {
        try? await tdSendChatAction(.chatActionUploadingDocument(.init(progress: 0)))
        let contents = displayedDocuments.map { url in
            InputMessageContent.inputMessageDocument(.init(
                caption: FormattedText(entities: getEntities(from: text), text: text.string),
                document: InputDocument(
                    disableContentTypeDetection: true,
                    document: .inputFileLocal(.init(path: url.path())),
                    thumbnail: nil,
                ),
            ))
        }
        if contents.count == 1, let content = contents.first {
            _ = try? await service.sendMessage(
                chatId: customChat.chat.id,
                inputMessageContent: content,
                options: nil,
                replyMarkup: nil,
                replyTo: getMessageReplyTo(from: replyMessage),
                topicId: nil,
            )
        } else if !contents.isEmpty {
            _ = try? await service.sendMessageAlbum(
                chatId: customChat.chat.id,
                inputMessageContents: contents,
                options: nil,
                replyTo: getMessageReplyTo(from: replyMessage),
                topicId: nil,
            )
        }
        try? await tdSendChatAction(.chatActionCancel)
    }
    
    func sendMessagePhotos() async {
        try? await tdSendChatAction(.chatActionUploadingPhoto(.init(progress: 0)))
        
        if displayedImages.count == 1, let photo = displayedImages.first {
            _ = try? await service.sendMessage(
                chatId: customChat.chat.id,
                inputMessageContent: makeInputMessageContent(for: photo.url),
                options: nil,
                replyMarkup: nil,
                replyTo: getMessageReplyTo(from: replyMessage),
                topicId: nil,
            )
        } else {
            let messageContents = displayedImages.map {
                makeInputMessageContent(for: $0.url)
            }
            _ = try? await service.sendMessageAlbum(
                chatId: customChat.chat.id,
                inputMessageContents: messageContents,
                options: nil,
                replyTo: getMessageReplyTo(from: replyMessage),
                topicId: nil,
            )
        }
        
        try? await tdSendChatAction(.chatActionCancel)
    }
    
    func makeInputMessageContent(for url: URL) -> InputMessageContent {
        let path = url.path()
        let pixelSize = imagePixelSize(at: url) ?? .zero
        let input = InputFile.inputFileLocal(.init(path: path))
        return .inputMessagePhoto(
            InputMessagePhoto(
                caption: FormattedText(entities: getEntities(from: text), text: text.string),
                hasSpoiler: false,
                photo: InputPhoto(
                    addedStickerFileIds: [],
                    height: Int(pixelSize.height),
                    photo: input,
                    // TDLib generates the appropriate thumbnail. Passing the
                    // original photo here made it process the full file twice.
                    thumbnail: nil,
                    video: nil,
                    width: Int(pixelSize.width),
                ),
                selfDestructType: nil,
                showCaptionAboveMedia: false,
            ),
        )
    }
    
    func sendMessageText() async {
        _ = try? await service.sendMessage(
            chatId: customChat.chat.id,
            inputMessageContent: .inputMessageText(
                .init(
                    clearDraft: true,
                    linkPreviewOptions: nil,
                    text: FormattedText(
                        entities: getEntities(from: text),
                        text: text.string,
                    ),
                ),
            ),
            options: nil,
            replyMarkup: nil,
            replyTo: getMessageReplyTo(from: replyMessage),
            topicId: nil,
        )
        
        try? await tdSendChatAction(.chatActionCancel)
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
        guard let customMessage else { return nil }
        return .inputMessageReplyToMessage(.init(
            checklistTaskId: 0,
            messageId: customMessage.message.id,
            pollOptionId: "",
            quote: nil,
        ))
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
    
    func getBytesWave(from waves: [UInt8]) -> [UInt8] {
        var bytesWave = [UInt8]()
        var count = 0
        for wave in waves {
            let index = bytesWave.count - 1
            switch count {
            case 0:
                bytesWave.append((wave & 0b0001_1111) << 3)
            case 1:
                bytesWave[index] = bytesWave.last! | ((wave & 0b0001_1100) >> 2)
                bytesWave.append((wave & 0b0000_0011) << 6)
            case 2:
                bytesWave[index] = bytesWave.last! | ((wave & 0b0001_1111) << 1)
            case 3:
                bytesWave[index] = bytesWave.last! | ((wave & 0b0001_0000) >> 4)
                bytesWave.append((wave & 0b0000_1111) << 4)
            case 4:
                bytesWave[index] = bytesWave.last! | ((wave & 0b0001_1110) >> 1)
                bytesWave.append((wave & 0b0000_0001) << 7)
            case 5:
                bytesWave[index] = bytesWave.last! | ((wave & 0b0001_1111) << 2)
            case 6:
                bytesWave[index] = bytesWave.last! | ((wave & 0b0001_1000) >> 3)
                bytesWave.append((wave & 0b0000_0111) << 5)
            case 7:
                bytesWave[index] = bytesWave.last! | wave
            default:
                break
            }
            count += count == 7 ? -7 : 1
        }
        return bytesWave
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
        
        let url = URL(filePath: NSTemporaryDirectory()).appending(path: "\(UUID().uuidString).ogg")
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
        try? FileManager.default.removeItem(at: savedVoiceNoteUrl)
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

        let intWave: [Int] = wave.compactMap { wave in
            let intWave = abs(Int(wave))
            if intWave == 120 || intWave == 160 {
                return nil
            }
            return intWave
        }
        let resultWave: [Int] = intWave.map { wave in
            let value = 32 - Int(Double(wave) * Double(32) / Double(66)) // 66 is a random number, need to be tested
            return value < 0 ? 0 : value
        }
        let collapsedWave: [Int] = resultWave.reduce([]) { result, element in
            if result.last != element {
                return result + [element]
            }
            return result
        }
        let endWave = collapsedWave.map { UInt8($0) }
        let bytesWave = getBytesWave(from: endWave)
        let waveform = Data(bytesWave).prefix(63)
        Task.background {
            try? await self.tdSendChatAction(.chatActionUploadingVoiceNote(.init(progress: 0)))
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
            NavigationStorage.shared.push(.customChat(chat, messageId: messageId))
        }
    }
}
