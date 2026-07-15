// MacSessionModel.swift

import AppKit
import AVFoundation
import Combine
import Foundation
import SwiftUI
import TDLibKit
import UniformTypeIdentifiers

// MARK: - MacMessageCapabilities

struct MacMessageCapabilities {
    let properties: MessageProperties
    let canReactWithHeart: Bool
}

// MARK: - MacMessageReplyContext

struct MacMessageReplyContext {
    let chatId: Int64
    let messageId: Int64?
    let senderName: String
    let quotedText: String
}

// MARK: - MacMessageSenderKey

private enum MacMessageSenderKey: Hashable {
    case chat(Int64)
    case user(Int64)
}

// MARK: - MacSessionModel

@MainActor @Observable final class MacSessionModel {
    // MARK: Lifecycle

    init() {
        self.session = TelegramSession()
        self.service = session
        observeSession()
    }

    // MARK: Internal

    var authorizationState: AuthorizationState?
    var authorizationStatus = "Starting Telegram…"
    var chatList = ChatListSnapshot.empty
    var selectedChatFolderId = MacChatFolderID.main
    var focusedChatId: Int64?
    var openedChatId: Int64?
    var messages = TelegramMessageSnapshot.empty(chatId: 0)
    var messageText = ""
    var editMessageText = ""
    var editingMessage: Message?
    var replyingToMessage: Message?
    var messageCapabilities = [Int64: MacMessageCapabilities]()
    var messageReplyContexts = [Int64: MacMessageReplyContext]()
    var messageForwardedFrom = [Int64: String]()
    var messageSenderNames = [Int64: String]()
    var messageActionError: String?
    var selectedDocumentURLs = [URL]()
    var selectedPhotoURLs = [URL]()
    var phoneNumber = ""
    var loginCode = ""
    var password = ""
    var loginError: String?
    var isLoadingChats = false
    var isLoadingMessages = false
    var isLoadingOlderMessages = false
    var isLoadingLatestMessages = false
    var canLoadOlderMessages = true
    var isRecordingVoice = false
    var voiceRecordingDuration: TimeInterval = 0
    var searchQuery = ""
    var chatSearchResults = [MacChatSearchResult]()
    var messageSearchResults = [MacMessageSearchResult]()
    var focusedSearchResult: MacSearchResultID?
    var isSearching = false
    var navigationTargetMessageId: Int64?
    var latestHistoryTargetMessageId: Int64?
    var openedUnreadCount = 0
    var openedLastReadInboxMessageId: Int64 = 0

    @ObservationIgnored var bootstrapTask: Task<Void, Never>?
    @ObservationIgnored var loadedChatFolderIds = Set<MacChatFolderID>()
    @ObservationIgnored var searchTask: Task<Void, Never>?
    @ObservationIgnored var searchGeneration: UInt64 = 0
    @ObservationIgnored var historyRequestGeneration: UInt64 = 0
    @ObservationIgnored let service: any TelegramService

    var chatItems: [ChatListItemState] {
        chatList.chatIds(in: selectedChatList).compactMap { chatList.items[$0] }
    }

    var openedChat: ChatListItemState? {
        guard let openedChatId else { return nil }
        return chatList.items[openedChatId]
    }

    func start() {
        guard !started else { return }
        started = true
        guard let directory = try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "BetterTG/td")
        else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        session.start(configuration: .init(
            apiHash: Secret.apiHash,
            apiId: Secret.apiId,
            applicationVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            databaseDirectory: directory.path(),
            deviceModel: Host.current().localizedName ?? "Mac",
            systemLanguageCode: Locale.current.identifier,
            systemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
        ))
    }

    func stop() {
        cancelVoiceRecording()
        historyRequestGeneration &+= 1
        selectedPhotoURLs = []
        selectedDocumentURLs = []
        openTask?.cancel()
        bootstrapTask?.cancel()
        session.close()
    }

    func submitPhoneNumber() {
        let normalized = phoneNumber.filter { $0.isNumber || $0 == "+" }
        guard !normalized.isEmpty else { return }
        runLoginRequest {
            try await self.service.setAuthenticationPhoneNumber(phoneNumber: normalized, settings: nil)
        }
    }

    func submitCode() {
        guard !loginCode.isEmpty else { return }
        runLoginRequest {
            try await self.service.checkAuthenticationCode(code: self.loginCode)
        }
    }

    func submitPassword() {
        guard !password.isEmpty else { return }
        runLoginRequest {
            try await self.service.checkAuthenticationPassword(password: self.password)
        }
    }

    func activateFocusedChat() {
        guard let focusedChatId else { return }
        activateChat(focusedChatId)
    }

    func activateChat(_ chatId: Int64, messageId: Int64? = nil) {
        focusedChatId = chatId
        latestHistoryTargetMessageId = nil
        navigationTargetMessageId = messageId
        if openedChatId == chatId {
            guard let messageId, messages.messages[messageId] == nil else { return }
            historyRequestGeneration &+= 1
            let generation = historyRequestGeneration
            openTask?.cancel()
            openTask = Task { [weak self] in
                guard let self else { return }
                let found = await loadInitialHistory(chatId: chatId, around: messageId)
                guard !Task.isCancelled, generation == historyRequestGeneration else { return }
                isLoadingMessages = false
                if !found.contains(where: { $0.id == messageId }) {
                    navigationTargetMessageId = nil
                }
            }
            return
        }

        let openingChat = chatList.items[chatId]
        openedUnreadCount = openingChat?.unreadCount ?? 0
        openedLastReadInboxMessageId = openingChat?.lastReadInboxMessageId ?? 0

        cancelVoiceRecording()
        selectedPhotoURLs = []
        selectedDocumentURLs = []

        let previousChatId = openedChatId
        openedChatId = chatId
        messages = .empty(chatId: chatId)
        editingMessage = nil
        replyingToMessage = nil
        editMessageText = ""
        messageCapabilities = [:]
        messageReplyContexts = [:]
        messageForwardedFrom = [:]
        messageSenderNames = [:]
        isLoadingMessages = true
        isLoadingOlderMessages = false
        isLoadingLatestMessages = false
        canLoadOlderMessages = true
        historyRequestGeneration &+= 1
        messageSubscription?.cancel()
        messageSubscription = service.messagePublisher(chatId: chatId)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                guard self?.openedChatId == snapshot.chatId else { return }
                self?.handleMessageSnapshot(snapshot)
            }

        openTask?.cancel()
        openTask = Task { [weak self] in
            guard let self else { return }
            if let previousChatId {
                _ = try? await service.closeChat(chatId: previousChatId)
            }
            guard !Task.isCancelled, openedChatId == chatId else { return }
            _ = try? await service.openChat(chatId: chatId)
            let historyMessages = await loadInitialHistory(chatId: chatId, around: messageId)
            guard !Task.isCancelled, openedChatId == chatId else { return }
            if let newestMessageId = historyMessages.max(by: { $0.id < $1.id })?.id {
                _ = try? await service.viewMessages(
                    chatId: chatId,
                    forceRead: true,
                    messageIds: [newestMessageId],
                    source: .messageSourceChatHistory,
                )
            }
            isLoadingMessages = false
        }
    }

    func submitComposer() {
        if !selectedDocumentURLs.isEmpty, editingMessage == nil {
            sendSelectedDocuments()
        } else if !selectedPhotoURLs.isEmpty, editingMessage == nil {
            sendSelectedPhotos()
        } else if editingMessage != nil {
            editMessage()
        } else {
            sendTextMessage()
        }
    }

    func choosePhotos() {
        guard !isRecordingVoice, editingMessage == nil else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose Photos"
        panel.prompt = "Attach"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK else { return }
        selectedDocumentURLs = []
        selectedPhotoURLs = panel.urls
    }

    func chooseDocuments() {
        guard !isRecordingVoice, editingMessage == nil else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose Files"
        panel.prompt = "Attach"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.item]
        guard panel.runModal() == .OK else { return }
        selectedPhotoURLs = []
        selectedDocumentURLs = panel.urls
    }

    func removeSelectedDocument(_ url: URL) {
        selectedDocumentURLs.removeAll { $0 == url }
    }

    func removeSelectedPhoto(_ url: URL) {
        selectedPhotoURLs.removeAll { $0 == url }
    }

    func startVoiceRecording() async {
        guard !isRecordingVoice, selectedDocumentURLs.isEmpty, selectedPhotoURLs.isEmpty,
              editingMessage == nil, let openedChatId
        else { return }
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            messageActionError = "Microphone access is required to record a voice message."
            return
        }

        MacVoicePlayer.shared.stop()
        let url = URL(filePath: NSTemporaryDirectory()).appending(path: "\(UUID().uuidString).ogg")
        let recorder = VoiceNoteRecorder()
        do {
            try recorder.start()
        } catch {
            messageActionError = "Voice recording could not start: \(error.localizedDescription)"
            return
        }

        voiceRecorder = recorder
        voiceRecordingURL = url
        voiceRecordingChatId = openedChatId
        voiceRecordingStartedAt = Foundation.Date()
        voiceRecordingDuration = 0
        isRecordingVoice = true
        recordingTimer?.cancel()
        recordingTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard let self, isRecordingVoice, let startedAt = voiceRecordingStartedAt else { return }
                voiceRecordingDuration = Foundation.Date().timeIntervalSince(startedAt)
            }
        }

        _ = try? await service.sendChatAction(
            action: .chatActionRecordingVoiceNote,
            businessConnectionId: nil,
            chatId: openedChatId,
            topicId: nil,
        )
    }

    func cancelVoiceRecording() {
        guard isRecordingVoice || voiceRecorder != nil else { return }
        let chatId = voiceRecordingChatId
        let url = voiceRecordingURL
        voiceRecorder?.cancel()
        resetVoiceRecordingState()
        if let url {
            try? FileManager.default.removeItem(at: url)
        }
        if let chatId {
            Task {
                _ = try? await service.sendChatAction(
                    action: .chatActionCancel,
                    businessConnectionId: nil,
                    chatId: chatId,
                    topicId: nil,
                )
            }
        }
    }

    func sendVoiceRecording() {
        guard let recorder = voiceRecorder,
              let url = voiceRecordingURL,
              let chatId = voiceRecordingChatId,
              openedChatId == chatId
        else {
            cancelVoiceRecording()
            return
        }

        let duration: Int
        do {
            duration = try max(1, Int(ceil(recorder.stopAndWrite(to: url))))
        } catch {
            messageActionError = "Voice recording could not be finalized: \(error.localizedDescription)"
            cancelVoiceRecording()
            return
        }

        let replyTo = replyingToMessage.map {
            InputMessageReplyTo.inputMessageReplyToMessage(.init(
                checklistTaskId: 0,
                messageId: $0.id,
                pollOptionId: "",
                quote: nil,
            ))
        }
        replyingToMessage = nil
        resetVoiceRecordingState()

        Task {
            do {
                _ = try? await service.sendChatAction(
                    action: .chatActionUploadingVoiceNote(.init(progress: 0)),
                    businessConnectionId: nil,
                    chatId: chatId,
                    topicId: nil,
                )
                _ = try await service.sendMessage(
                    chatId: chatId,
                    inputMessageContent: .inputMessageVoiceNote(.init(
                        caption: FormattedText(entities: [], text: ""),
                        duration: duration,
                        selfDestructType: nil,
                        voiceNote: .inputFileLocal(.init(path: url.path())),
                        waveform: Data(),
                    )),
                    options: nil,
                    replyMarkup: nil,
                    replyTo: replyTo,
                    topicId: nil,
                )
                _ = try? await service.sendChatAction(
                    action: .chatActionCancel,
                    businessConnectionId: nil,
                    chatId: chatId,
                    topicId: nil,
                )
            } catch {
                messageActionError = error.localizedDescription
            }
        }
    }

    func localPhotoPath(fileId: Int) async -> String? {
        if let cachedPath = photoPaths[fileId] {
            return cachedPath
        }
        guard let file = try? await service.downloadFile(
            fileId: fileId,
            limit: 0,
            offset: 0,
            priority: 24,
            synchronous: true,
        ), file.local.isDownloadingCompleted, !file.local.path.isEmpty
        else { return nil }
        photoPaths[fileId] = file.local.path
        return file.local.path
    }

    func localDocumentPath(fileId: Int) async -> String? {
        if let cachedPath = documentPaths[fileId] {
            return cachedPath
        }
        guard let file = try? await service.downloadFile(
            fileId: fileId,
            limit: 0,
            offset: 0,
            priority: 24,
            synchronous: true,
        ), file.local.isDownloadingCompleted, !file.local.path.isEmpty
        else { return nil }
        documentPaths[fileId] = file.local.path
        return file.local.path
    }

    func localVideoPath(fileId: Int) async -> String? {
        if let cachedPath = videoPaths[fileId] {
            return cachedPath
        }
        guard let file = try? await service.downloadFile(
            fileId: fileId,
            limit: 0,
            offset: 0,
            priority: 32,
            synchronous: true,
        ), file.local.isDownloadingCompleted, !file.local.path.isEmpty
        else { return nil }
        videoPaths[fileId] = file.local.path
        return file.local.path
    }

    func beginReply(to message: Message) {
        editingMessage = nil
        editMessageText = ""
        replyingToMessage = message
    }

    func cancelReplyOrEdit() {
        editingMessage = nil
        replyingToMessage = nil
        editMessageText = ""
    }

    func beginEditing(_ message: Message) {
        guard let text = TelegramMessageEditing.editableFormattedText(from: message)?.text else { return }
        selectedPhotoURLs = []
        selectedDocumentURLs = []
        replyingToMessage = nil
        editingMessage = message
        editMessageText = text
    }

    func loadCapabilities(for message: Message) async {
        guard messageCapabilities[message.id] == nil,
              !loadingCapabilityMessageIds.contains(message.id),
              openedChatId == message.chatId
        else { return }
        loadingCapabilityMessageIds.insert(message.id)
        defer { loadingCapabilityMessageIds.remove(message.id) }

        guard let properties = try? await service.getMessageProperties(
            chatId: message.chatId,
            messageId: message.id,
        ) else { return }
        let availableReactions = try? await service.getMessageAvailableReactions(
            chatId: message.chatId,
            messageId: message.id,
            rowSize: 8,
        )
        let heart = ReactionType.reactionTypeEmoji(.init(emoji: "❤"))
        let canReactWithHeart = availableReactions?.unavailabilityReason == nil
            && ((availableReactions?.topReactions ?? [])
                + (availableReactions?.recentReactions ?? [])
                + (availableReactions?.popularReactions ?? []))
            .contains { $0.type == heart }
        guard openedChatId == message.chatId else { return }
        messageCapabilities[message.id] = MacMessageCapabilities(
            properties: properties,
            canReactWithHeart: canReactWithHeart,
        )
    }

    func loadReplyContext(for message: Message) async {
        guard messageReplyContexts[message.id] == nil,
              !loadingReplyContextMessageIds.contains(message.id),
              case .messageReplyToMessage(let reply) = message.replyTo,
              openedChatId == message.chatId
        else { return }
        loadingReplyContextMessageIds.insert(message.id)
        defer { loadingReplyContextMessageIds.remove(message.id) }

        let repliedMessage: Message? =
            if reply.messageId != 0 {
                try? await service.getMessage(
                    chatId: reply.chatId == 0 ? message.chatId : reply.chatId,
                    messageId: reply.messageId,
                )
            } else {
                nil
            }

        let senderName: String =
            switch repliedMessage?.senderId {
            case .messageSenderUser(let sender):
                await (try? service.getUser(userId: sender.userId))?.firstName ?? "message"
            case .messageSenderChat(let sender):
                await (try? service.getChat(chatId: sender.chatId))?.title ?? "message"
            case nil:
                "message"
            }

        let quotedText: String =
            if let explicitQuote = reply.quote?.text.text, !explicitQuote.isEmpty {
                explicitQuote
            } else if let repliedMessage {
                telegramMessageContentDescription(repliedMessage)
            } else if let content = reply.content {
                telegramMessageContentDescription(content)
            } else {
                "Message"
            }
        guard openedChatId == message.chatId else { return }
        messageReplyContexts[message.id] = MacMessageReplyContext(
            chatId: reply.chatId == 0 ? message.chatId : reply.chatId,
            messageId: reply.messageId == 0 ? repliedMessage?.id : reply.messageId,
            senderName: senderName,
            quotedText: telegramQuotedMessageExcerpt(quotedText),
        )
    }

    func navigateToRepliedMessage(from message: Message) {
        guard let context = messageReplyContexts[message.id], let messageId = context.messageId else { return }
        if context.chatId == openedChatId {
            activateChat(context.chatId, messageId: messageId)
            return
        }
        Task { [weak self] in
            guard let self else { return }
            guard let chat = try? await service.getChat(chatId: context.chatId) else {
                messageActionError = "This chat is private or unavailable."
                return
            }
            activateResolvedChat(chat, messageId: messageId)
        }
    }

    func navigateToForwardOrigin(from message: Message) {
        guard let origin = message.forwardInfo?.origin else { return }
        Task { [weak self] in
            guard let self else { return }
            let destination: (chat: Chat, messageId: Int64?)?
            switch origin {
            case .messageOriginUser(let user):
                if let chat = try? await service.createPrivateChat(force: false, userId: user.senderUserId) {
                    destination = (chat, nil)
                } else {
                    destination = nil
                }
            case .messageOriginChat(let chat):
                if let resolvedChat = try? await service.getChat(chatId: chat.senderChatId) {
                    destination = (resolvedChat, nil)
                } else {
                    destination = nil
                }
            case .messageOriginChannel(let channel):
                if let chat = try? await service.getChat(chatId: channel.chatId) {
                    destination = (chat, channel.messageId == 0 ? nil : channel.messageId)
                } else {
                    destination = nil
                }
            case .messageOriginHiddenUser:
                return
            }
            guard let destination else {
                messageActionError = "This user or chat is private or unavailable."
                return
            }
            activateResolvedChat(destination.chat, messageId: destination.messageId)
        }
    }

    func loadForwardedFrom(for message: Message) async {
        guard messageForwardedFrom[message.id] == nil,
              !loadingForwardedMessageIds.contains(message.id),
              let origin = message.forwardInfo?.origin,
              openedChatId == message.chatId
        else { return }
        loadingForwardedMessageIds.insert(message.id)
        defer { loadingForwardedMessageIds.remove(message.id) }

        let name: String?
        switch origin {
        case .messageOriginChat(let chat):
            let title = await (try? service.getChat(chatId: chat.senderChatId))?.title
            name = title.map { chat.authorSignature.isEmpty ? $0 : "\($0) (\(chat.authorSignature))" }
                ?? (chat.authorSignature.isEmpty ? nil : chat.authorSignature)
        case .messageOriginChannel(let channel):
            let title = await (try? service.getChat(chatId: channel.chatId))?.title
            name = title.map { channel.authorSignature.isEmpty ? $0 : "\($0) (\(channel.authorSignature))" }
                ?? (channel.authorSignature.isEmpty ? nil : channel.authorSignature)
        case .messageOriginHiddenUser(let user):
            name = user.senderName
        case .messageOriginUser(let user):
            name = await (try? service.getUser(userId: user.senderUserId))?.firstName
        }
        guard openedChatId == message.chatId, let name, !name.isEmpty else { return }
        messageForwardedFrom[message.id] = name
    }

    func loadSenderName(for message: Message) async {
        guard !message.isOutgoing,
              messageSenderNames[message.id] == nil,
              openedChatId == message.chatId
        else { return }

        let resolvedSenderKey: MacMessageSenderKey =
            switch message.senderId {
            case .messageSenderUser(let sender):
                .user(sender.userId)
            case .messageSenderChat(let sender):
                .chat(sender.chatId)
            }
        if let cachedName = senderNamesByKey[resolvedSenderKey] {
            messageSenderNames[message.id] = cachedName
            return
        }
        let request: Task<String?, Never>
        if let pendingRequest = senderNameRequests[resolvedSenderKey] {
            request = pendingRequest
        } else {
            request = Task { [service] in
                switch resolvedSenderKey {
                case .user(let userId):
                    guard let user = try? await service.getUser(userId: userId) else { return nil }
                    return "\(user.firstName) \(user.lastName)".trimmingCharacters(in: .whitespaces)
                case .chat(let chatId):
                    return try? await service.getChat(chatId: chatId).title
                }
            }
            senderNameRequests[resolvedSenderKey] = request
        }
        let name = await request.value
        senderNameRequests[resolvedSenderKey] = nil
        guard let name, !name.isEmpty else { return }
        senderNamesByKey[resolvedSenderKey] = name
        guard openedChatId == message.chatId else { return }
        messageSenderNames[message.id] = name
        for visibleMessage in messages.messages.values where senderKey(for: visibleMessage) == resolvedSenderKey {
            messageSenderNames[visibleMessage.id] = name
        }
    }

    func cachedSenderName(for message: Message) -> String? {
        messageSenderNames[message.id] ?? senderNamesByKey[senderKey(for: message)]
    }

    func toggleRead(for chat: ChatListItemState) {
        performMessageAction {
            await TelegramChatActions.toggleRead(
                service: self.service,
                chatId: chat.chatId,
                unreadCount: chat.unreadCount,
                lastMessageId: chat.lastMessage?.id,
                isMarkedAsUnread: chat.isMarkedAsUnread,
            )
        }
    }

    func togglePinned(for chat: ChatListItemState, in chatList: ChatList) {
        let isPinned = chat.position(in: chatList)?.isPinned == true
        performMessageAction {
            await TelegramChatActions.togglePinned(
                service: self.service,
                chatId: chat.chatId,
                chatList: chatList,
                newIsPinned: !isPinned,
            )
        }
    }

    func toggleArchived(_ chat: ChatListItemState) {
        let isArchived = chat.position(in: .chatListArchive) != nil
        performMessageAction {
            await TelegramChatActions.toggleArchived(
                service: self.service,
                chatId: chat.chatId,
                isCurrentlyArchived: isArchived,
            )
        }
    }

    func setMuteDuration(_ duration: Int, for chat: ChatListItemState) {
        guard let current = chat.notificationSettings else { return }
        performMessageAction {
            await TelegramChatActions.setMuteDuration(
                service: self.service,
                chatId: chat.chatId,
                duration: duration,
                current: current,
            )
        }
    }

    func deleteChat(_ chat: ChatListItemState, forEveryone: Bool) {
        performMessageAction {
            await TelegramChatActions.deleteChatHistory(
                service: self.service,
                chatId: chat.chatId,
                forEveryone: forEveryone,
            )
        }
    }

    func reactWithHeart(to message: Message) {
        performMessageAction {
            _ = try await self.service.addMessageReaction(
                chatId: message.chatId,
                isBig: false,
                messageId: message.id,
                reactionType: .reactionTypeEmoji(.init(emoji: "❤")),
                updateRecentReactions: true,
            )
        }
    }

    func togglePin(for message: Message) {
        performMessageAction {
            _ =
                if message.isPinned {
                    try await self.service.unpinChatMessage(chatId: message.chatId, messageId: message.id)
                } else {
                    try await self.service.pinChatMessage(
                        chatId: message.chatId,
                        disableNotification: false,
                        messageId: message.id,
                        onlyForSelf: false,
                    )
                }
        }
    }

    func delete(_ message: Message, forEveryone: Bool) {
        performMessageAction {
            _ = try await self.service.deleteMessages(
                chatId: message.chatId,
                messageIds: [message.id],
                revoke: forEveryone,
            )
        }
    }

    func localVoiceNotePath(fileId: Int) async -> String? {
        if let cachedPath = voiceNotePaths[fileId] {
            return cachedPath
        }
        guard let file = try? await service.downloadFile(
            fileId: fileId,
            limit: 0,
            offset: 0,
            priority: 32,
            synchronous: true,
        ), file.local.isDownloadingCompleted, !file.local.path.isEmpty
        else { return nil }
        voiceNotePaths[fileId] = file.local.path
        return file.local.path
    }

    // MARK: Private

    @ObservationIgnored private var cancellables = Set<AnyCancellable>()
    @ObservationIgnored private var messageSubscription: AnyCancellable?
    @ObservationIgnored private var loadingCapabilityMessageIds = Set<Int64>()
    @ObservationIgnored private var loadingReplyContextMessageIds = Set<Int64>()
    @ObservationIgnored private var loadingForwardedMessageIds = Set<Int64>()
    @ObservationIgnored private var senderNameRequests = [MacMessageSenderKey: Task<String?, Never>]()
    @ObservationIgnored private var senderNamesByKey = [MacMessageSenderKey: String]()
    @ObservationIgnored private var openTask: Task<Void, Never>?
    @ObservationIgnored private var documentPaths = [Int: String]()
    @ObservationIgnored private var photoPaths = [Int: String]()
    @ObservationIgnored private var videoPaths = [Int: String]()
    @ObservationIgnored private var recordingTimer: Task<Void, Never>?
    @ObservationIgnored private let notifications = MacLocalNotifications()
    @ObservationIgnored private let session: TelegramSession
    @ObservationIgnored private var started = false
    @ObservationIgnored private var voiceNotePaths = [Int: String]()
    @ObservationIgnored private var voiceRecorder: VoiceNoteRecorder?
    @ObservationIgnored private var voiceRecordingChatId: Int64?
    @ObservationIgnored private var voiceRecordingStartedAt: Foundation.Date?
    @ObservationIgnored private var voiceRecordingURL: URL?

    private static func title(for state: AuthorizationState) -> String {
        switch state {
        case .authorizationStateReady: "Telegram is ready"
        case .authorizationStateWaitPhoneNumber: "Phone number required"
        case .authorizationStateWaitCode: "Login code required"
        case .authorizationStateWaitPassword: "Two-step verification required"
        case .authorizationStateWaitTdlibParameters: "Configuring Telegram…"
        case .authorizationStateClosed: "Telegram session closed"
        case .authorizationStateClosing: "Closing Telegram session…"
        case .authorizationStateLoggingOut: "Logging out…"
        default: "Additional authorization required"
        }
    }

    private func senderKey(for message: Message) -> MacMessageSenderKey {
        switch message.senderId {
        case .messageSenderUser(let sender): .user(sender.userId)
        case .messageSenderChat(let sender): .chat(sender.chatId)
        }
    }

    private func activateResolvedChat(_ chat: Chat, messageId: Int64?) {
        service.mergeChatListChats([chat])
        if chatList.items[chat.id] == nil {
            chatList.items[chat.id] = ChatListItemState(
                chatId: chat.id,
                title: chat.title,
                positions: chat.positions,
                unreadCount: chat.unreadCount,
                lastMessage: chat.lastMessage,
                draftMessage: chat.draftMessage,
                notificationSettings: chat.notificationSettings,
                lastReadInboxMessageId: chat.lastReadInboxMessageId,
                lastReadOutboxMessageId: chat.lastReadOutboxMessageId,
                isMarkedAsUnread: chat.isMarkedAsUnread,
                canBeDeletedOnlyForSelf: chat.canBeDeletedOnlyForSelf,
                canBeDeletedForAllUsers: chat.canBeDeletedForAllUsers,
            )
        }
        activateChat(chat.id, messageId: messageId)
    }

    private func sendTextMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let openedChatId, !text.isEmpty else { return }
        let replyTo = replyingToMessage.map {
            InputMessageReplyTo.inputMessageReplyToMessage(.init(
                checklistTaskId: 0,
                messageId: $0.id,
                pollOptionId: "",
                quote: nil,
            ))
        }
        messageText = ""
        replyingToMessage = nil
        Task {
            do {
                _ = try await service.sendMessage(
                    chatId: openedChatId,
                    inputMessageContent: .inputMessageText(.init(
                        clearDraft: true,
                        linkPreviewOptions: nil,
                        text: FormattedText(entities: [], text: text),
                    )),
                    options: nil,
                    replyMarkup: nil,
                    replyTo: replyTo,
                    topicId: nil,
                )
            } catch {
                messageActionError = error.localizedDescription
            }
        }
    }

    private func sendSelectedPhotos() {
        guard let chatId = openedChatId, !selectedPhotoURLs.isEmpty else { return }
        let urls = selectedPhotoURLs
        let caption = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        let replyTo = replyingToMessage.map {
            InputMessageReplyTo.inputMessageReplyToMessage(.init(
                checklistTaskId: 0,
                messageId: $0.id,
                pollOptionId: "",
                quote: nil,
            ))
        }
        let contents = urls.compactMap { inputPhotoContent(url: $0, caption: caption) }
        guard !contents.isEmpty else {
            messageActionError = "The selected files could not be read as photos."
            return
        }

        selectedPhotoURLs = []
        messageText = ""
        replyingToMessage = nil
        Task {
            do {
                _ = try? await service.sendChatAction(
                    action: .chatActionUploadingPhoto(.init(progress: 0)),
                    businessConnectionId: nil,
                    chatId: chatId,
                    topicId: nil,
                )
                // swiftformat:disable:next conditionalAssignment
                if contents.count == 1, let content = contents.first {
                    _ = try await service.sendMessage(
                        chatId: chatId,
                        inputMessageContent: content,
                        options: nil,
                        replyMarkup: nil,
                        replyTo: replyTo,
                        topicId: nil,
                    )
                } else {
                    _ = try await service.sendMessageAlbum(
                        chatId: chatId,
                        inputMessageContents: contents,
                        options: nil,
                        replyTo: replyTo,
                        topicId: nil,
                    )
                }
                _ = try? await service.sendChatAction(
                    action: .chatActionCancel,
                    businessConnectionId: nil,
                    chatId: chatId,
                    topicId: nil,
                )
            } catch {
                messageActionError = error.localizedDescription
            }
        }
    }

    private func sendSelectedDocuments() {
        guard let chatId = openedChatId, !selectedDocumentURLs.isEmpty else { return }
        let caption = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        let replyTo = replyingToMessage.map {
            InputMessageReplyTo.inputMessageReplyToMessage(.init(
                checklistTaskId: 0,
                messageId: $0.id,
                pollOptionId: "",
                quote: nil,
            ))
        }
        let contents = selectedDocumentURLs.map { url in
            InputMessageContent.inputMessageDocument(.init(
                caption: FormattedText(entities: [], text: caption),
                document: InputDocument(
                    disableContentTypeDetection: true,
                    document: .inputFileLocal(.init(path: url.path())),
                    thumbnail: nil,
                ),
            ))
        }

        selectedDocumentURLs = []
        messageText = ""
        replyingToMessage = nil
        Task {
            do {
                _ = try? await service.sendChatAction(
                    action: .chatActionUploadingDocument(.init(progress: 0)),
                    businessConnectionId: nil,
                    chatId: chatId,
                    topicId: nil,
                )
                // swiftformat:disable:next conditionalAssignment
                if contents.count == 1, let content = contents.first {
                    _ = try await service.sendMessage(
                        chatId: chatId,
                        inputMessageContent: content,
                        options: nil,
                        replyMarkup: nil,
                        replyTo: replyTo,
                        topicId: nil,
                    )
                } else {
                    _ = try await service.sendMessageAlbum(
                        chatId: chatId,
                        inputMessageContents: contents,
                        options: nil,
                        replyTo: replyTo,
                        topicId: nil,
                    )
                }
                _ = try? await service.sendChatAction(
                    action: .chatActionCancel,
                    businessConnectionId: nil,
                    chatId: chatId,
                    topicId: nil,
                )
            } catch {
                messageActionError = error.localizedDescription
            }
        }
    }

    private func inputPhotoContent(url: URL, caption: String) -> InputMessageContent? {
        guard let image = NSImage(contentsOf: url), image.size.width > 0, image.size.height > 0 else { return nil }
        return .inputMessagePhoto(.init(
            caption: FormattedText(entities: [], text: caption),
            hasSpoiler: false,
            photo: InputPhoto(
                addedStickerFileIds: [],
                height: Int(image.size.height),
                photo: .inputFileLocal(.init(path: url.path())),
                thumbnail: nil,
                video: nil,
                width: Int(image.size.width),
            ),
            selfDestructType: nil,
            showCaptionAboveMedia: false,
        ))
    }

    private func resetVoiceRecordingState() {
        recordingTimer?.cancel()
        recordingTimer = nil
        voiceRecorder = nil
        voiceRecordingURL = nil
        voiceRecordingChatId = nil
        voiceRecordingStartedAt = nil
        voiceRecordingDuration = 0
        isRecordingVoice = false
    }

    private func editMessage() {
        guard let message = editingMessage else { return }
        let text = editMessageText.trimmingCharacters(in: .whitespacesAndNewlines)
        if case .messageText = message.content, text.isEmpty {
            return
        }
        editingMessage = nil
        editMessageText = ""

        performMessageAction {
            await TelegramMessageEditing.editMessage(
                service: self.service,
                chatId: message.chatId,
                messageId: message.id,
                messageContent: message.content,
                newText: FormattedText(entities: [], text: text),
            )
        }
    }

    private func performMessageAction(_ action: @escaping @MainActor () async throws -> Void) {
        messageActionError = nil
        Task {
            do {
                try await action()
            } catch {
                messageActionError = error.localizedDescription
            }
        }
    }

    private func handleMessageSnapshot(_ snapshot: TelegramMessageSnapshot) {
        messages = snapshot
        let messageId: Int64? =
            switch snapshot.change {
            case .messageEdited(let update):
                update.messageId
            case .messagePinChanged(let update):
                update.messageId
            default:
                nil
            }
        guard let messageId else { return }
        messageCapabilities[messageId] = nil
        Task {
            guard let refreshed = try? await service.getMessage(
                chatId: snapshot.chatId,
                messageId: messageId,
            ), openedChatId == snapshot.chatId
            else { return }
            service.mergeMessages(chatId: snapshot.chatId, messages: [refreshed])
        }
    }

    private func observeSession() {
        service.authorizationStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.applyAuthorizationState(state)
            }
            .store(in: &cancellables)

        service.chatListPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                self?.applyChatListSnapshot(snapshot)
            }
            .store(in: &cancellables)

        service.updatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] update in
                self?.handleNotificationUpdate(update)
            }
            .store(in: &cancellables)
    }

    private func applyAuthorizationState(_ state: AuthorizationState) {
        authorizationState = state
        authorizationStatus = Self.title(for: state)
        if case .authorizationStateReady = state {
            bootstrapChats()
            Task { await notifications.requestAuthorization() }
        }
    }

    private func handleNotificationUpdate(_ update: Update) {
        guard case .updateNewMessage(let value) = update,
              !value.message.isOutgoing,
              openedChatId != value.message.chatId || !NSApplication.shared.isActive
        else { return }

        let title = chatList.items[value.message.chatId]?.title ?? "BetterTG"
        let body = macMessageText(value.message)
        Task {
            await notifications.deliver(chatId: value.message.chatId, title: title, body: body)
        }
    }

    private func runLoginRequest(_ operation: @escaping @MainActor () async throws -> Ok) {
        loginError = nil
        Task {
            do {
                _ = try await operation()
            } catch {
                loginError = error.localizedDescription
            }
        }
    }
}
