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
    let availableReactions: [AvailableReaction]
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
        let session = TelegramSession()
        self.session = session
        self.service = session
        self.pushNotifications = TelegramApplePushRegistration(
            service: session,
            isAppSandbox: Self.isAppSandbox,
        )
        observeSession()
    }

    // MARK: Internal

    var authorizationState: AuthorizationState?
    var authorizationStatus = "Starting Telegram…"
    var sessionEnded = false
    var canReauthenticate = false
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
    var messageServiceDescriptions = [Int64: String]()
    var messageActionError: String?
    var selectedDocumentURLs = [URL]()
    var selectedPhotoURLs = [URL]()
    var countryNumbers = [PhoneNumberInfo]()
    var selectedCountryNumber: PhoneNumberInfo?
    var callingCode = ""
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
    var conversationHeaderBaseStatus: String?
    var conversationHeaderActivities = [MessageSender: ChatAction]()

    @ObservationIgnored var bootstrapTask: Task<Void, Never>?
    @ObservationIgnored var loadedChatFolderIds = Set<MacChatFolderID>()
    @ObservationIgnored var searchTask: Task<Void, Never>?
    @ObservationIgnored var searchGeneration: UInt64 = 0
    @ObservationIgnored var historyRequestGeneration: UInt64 = 0
    @ObservationIgnored var displayedMessageLimit = 30
    @ObservationIgnored var displayedMessageAnchorId: Int64?
    @ObservationIgnored var service: any TelegramService

    @ObservationIgnored var conversationHeaderTask: Task<Void, Never>?
    @ObservationIgnored var openedChatType: ChatType?

    var chatItems: [ChatListItemState] {
        chatList.chatIds(in: selectedChatList).compactMap { chatList.items[$0] }
    }

    var formattedPhoneNumber: String {
        TelegramPhoneNumber.display(callingCode: callingCode, number: phoneNumber)
    }

    var openedChat: ChatListItemState? {
        guard let openedChatId else { return nil }
        return chatList.items[openedChatId]
    }

    func start() {
        guard !started else { return }
        started = true
        pushNotifications.start()
        guard let directory = try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "BetterTG/\(Self.databaseDirectoryName)")
        else { return }
        if UserDefaults.standard.object(forKey: Self.authorizationHistoryDefaultsKey) == nil {
            databaseExistedBeforeStart = FileManager.default.fileExists(atPath: directory.path())
        }
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
        isStopping = true
        pushNotifications.stop()
        cancelVoiceRecording()
        historyRequestGeneration &+= 1
        conversationHeaderTask?.cancel()
        selectedPhotoURLs = []
        selectedDocumentURLs = []
        countryLoadTask?.cancel()
        openTask?.cancel()
        bootstrapTask?.cancel()
        session.close()
    }

    func reauthenticate() {
        guard sessionEnded, canReauthenticate else { return }
        UserDefaults.standard.set(false, forKey: Self.wasAuthorizedDefaultsKey)

        if canReuseSessionForReauthentication {
            canReuseSessionForReauthentication = false
            sessionEnded = false
            canReauthenticate = false
            authorizationStatus = "Phone number required"
            loadCountriesIfNeeded()
            return
        }

        cancelWorkForSessionReplacement()
        let previousSession = session
        let replacementSession = TelegramSession()
        session = replacementSession
        service = replacementSession
        pushNotifications.replaceService(replacementSession)
        observeSession()

        authorizationState = nil
        authorizationStatus = "Preparing reauthentication…"
        sessionEnded = false
        canReauthenticate = false
        isStopping = false
        started = false

        previousSession.close()
        start()
    }

    func submitPhoneNumber() {
        guard let normalized = TelegramPhoneNumber.normalized(
            callingCode: callingCode,
            number: phoneNumber,
        ) else { return }
        runLoginRequest {
            try await self.service.setAuthenticationPhoneNumber(phoneNumber: normalized, settings: nil)
        }
    }

    func didRegisterForRemoteNotifications(deviceToken: Data) {
        pushNotifications.didRegister(deviceToken: deviceToken)
    }

    func didFailToRegisterForRemoteNotifications(error: any Swift.Error) {
        print("APNs registration failed: \(error.localizedDescription)")
    }

    func processRemoteNotification(userInfo: [AnyHashable: Any]) async {
        do {
            try await pushNotifications.process(userInfo: userInfo)
        } catch {
            print("TDLib push processing failed: \(error.localizedDescription)")
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

    func selectCountry(_ country: PhoneNumberInfo) {
        selectedCountryNumber = country
        callingCode = country.phoneNumberPrefix
        preferredCountryId = country.country
    }

    @discardableResult func updateCallingCode(_ value: String) -> Bool {
        let resolution = TelegramPhoneNumber.resolveCallingCode(
            value,
            countries: countryNumbers,
            preferredCountryId: preferredCountryId,
        )
        callingCode = resolution.callingCode
        selectedCountryNumber = resolution.country
        return resolution.shouldAdvanceToNumber
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
            displayedMessageLimit = max(displayedMessageLimit, 51)
            displayedMessageAnchorId = messageId
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
        displayedMessageLimit = messageId == nil ? 30 : 51
        displayedMessageAnchorId = messageId
        prepareConversationHeader(for: chatId, fallbackKind: openingChat?.kind)
        messages = .empty(chatId: chatId)
        editingMessage = nil
        replyingToMessage = nil
        editMessageText = ""
        messageCapabilities = [:]
        messageReplyContexts = [:]
        messageForwardedFrom = [:]
        messageSenderNames = [:]
        messageServiceDescriptions = [:]
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
                // Closing the old chat is independent from opening the new one. Waiting for its
                // TDLib round trip delayed the new chat's local-history request for no UI benefit.
                Task { _ = try? await service.closeChat(chatId: previousChatId) }
            }
            guard !Task.isCancelled, openedChatId == chatId else { return }
            _ = try? await service.openChat(chatId: chatId)
            let historyMessages: [Message]
            if messageId == nil,
               messages.hasMergedHistory,
               !messages.orderedMessageIds.isEmpty
            {
                // The subscription already delivered this chat's retained history. Fetching and
                // merging the same page again only increments the snapshot version and forces a
                // second table refresh immediately after the cached rows became visible.
                historyMessages = messages.orderedMessageIds.compactMap { messages.messages[$0] }
            } else {
                historyMessages = await loadInitialHistory(chatId: chatId, around: messageId)
            }
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

    @discardableResult
    func attachPastedFiles(_ urls: [URL]) -> Bool {
        guard !isRecordingVoice, editingMessage == nil else { return false }
        let pastedFiles = urls.filter { url in
            guard url.isFileURL else { return false }
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                && !isDirectory.boolValue
        }
        guard !pastedFiles.isEmpty else { return false }

        var seenURLs = Set<URL>()
        let combined = (selectedPhotoURLs + selectedDocumentURLs + pastedFiles).filter {
            seenURLs.insert($0).inserted
        }
        if combined.allSatisfy(isImageAttachment) {
            selectedDocumentURLs = []
            selectedPhotoURLs = combined
        } else {
            selectedPhotoURLs = []
            selectedDocumentURLs = combined
        }
        return true
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
        let url = TelegramVoiceNoteSending.temporaryFileURL()
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
            TelegramVoiceNoteStaging.shared.discard(fileURL: url)
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

        let replyTo = TelegramMessageSending.replyTo(messageId: replyingToMessage?.id)
        replyingToMessage = nil
        resetVoiceRecordingState()

        Task {
            do {
                try await TelegramVoiceNoteSending.send(
                    service: service,
                    chatId: chatId,
                    url: url,
                    caption: FormattedText(entities: [], text: ""),
                    duration: duration,
                    waveform: Data(),
                    replyTo: replyTo,
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
        guard openedChatId == message.chatId else { return }
        messageCapabilities[message.id] = MacMessageCapabilities(
            properties: properties,
            availableReactions: availableReactions.map(telegramAvailableReactions) ?? [],
        )
    }

    func loadServiceDescription(for message: Message) async {
        guard TelegramServiceMessage.isServiceMessage(message.content),
              messageServiceDescriptions[message.id] == nil,
              !loadingServiceMessageIds.contains(message.id),
              openedChatId == message.chatId
        else { return }
        loadingServiceMessageIds.insert(message.id)
        defer { loadingServiceMessageIds.remove(message.id) }

        guard let description = await TelegramServiceMessage.description(service: service, message: message),
              openedChatId == message.chatId
        else { return }
        messageServiceDescriptions[message.id] = description
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
            await activateResolvedChat(chat, messageId: messageId)
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
            await activateResolvedChat(destination.chat, messageId: destination.messageId)
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

        let name = await TelegramMessageOrigin.displayName(service: service, origin: origin)
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
        let ownsRequest: Bool
        if let pendingRequest = senderNameRequests[resolvedSenderKey] {
            request = pendingRequest
            ownsRequest = false
        } else {
            let senderId = message.senderId
            request = Task { [service] in
                await TelegramSenderName.displayName(service: service, senderId: senderId)
            }
            senderNameRequests[resolvedSenderKey] = request
            ownsRequest = true
        }
        let name = await request.value
        guard let name, !name.isEmpty else { return }
        if !ownsRequest {
            guard openedChatId == message.chatId,
                  messageSenderNames[message.id] != name
            else { return }
            messageSenderNames[message.id] = name
            return
        }

        senderNameRequests[resolvedSenderKey] = nil
        senderNamesByKey[resolvedSenderKey] = name
        guard openedChatId == message.chatId else { return }
        for visibleMessage in messages.messages.values where
            senderKey(for: visibleMessage) == resolvedSenderKey && messageSenderNames[visibleMessage.id] != name
        {
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

    func clearChatHistory(_ chat: ChatListItemState, forEveryone: Bool) {
        performMessageAction {
            await TelegramChatActions.clearChatHistory(
                service: self.service,
                chatId: chat.chatId,
                forEveryone: forEveryone,
            )
        }
    }

    func leaveChat(_ chat: ChatListItemState) {
        performMessageAction {
            await TelegramChatActions.leaveChat(service: self.service, chatId: chat.chatId)
        }
    }

    func toggleReaction(_ reaction: ReactionType, on message: Message) {
        performMessageAction {
            try await TelegramMessageActions.toggleReaction(
                service: self.service,
                message: message,
                reaction: reaction,
            )
        }
    }

    func togglePin(for message: Message) {
        performMessageAction {
            try await TelegramMessageActions.togglePinned(service: self.service, message: message)
        }
    }

    func delete(_ message: Message, forEveryone: Bool) {
        performMessageAction {
            try await TelegramMessageActions.delete(
                service: self.service,
                chatId: message.chatId,
                messageIds: [message.id],
                forEveryone: forEveryone,
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

    func activateResolvedChat(_ chat: Chat, messageId: Int64?) async {
        service.mergeChatListChats([chat])
        if chatList.items[chat.id] == nil {
            let membership = await service.resolveMembership(for: chat)
            chatList.items[chat.id] = ChatListItemState(chat, membership: membership)
        }
        activateChat(chat.id, messageId: messageId)
    }

    func performMessageAction(_ action: @escaping @MainActor () async throws -> Void) {
        messageActionError = nil
        Task {
            do {
                try await action()
            } catch {
                messageActionError = error.localizedDescription
            }
        }
    }

    // MARK: Private

    private static var databaseDirectoryName: String {
        #if DEBUG
        if CommandLine.arguments.contains("-BetterTGLoginTestSession") {
            return "td-login-test"
        }
        #endif
        return "td"
    }

    private static var wasAuthorizedDefaultsKey: String {
        "BetterTGMac.wasAuthorized.\(databaseDirectoryName)"
    }

    private static var authorizationHistoryDefaultsKey: String {
        "BetterTGMac.authorizationHistoryInitialized.\(databaseDirectoryName)"
    }

    private static var isAppSandbox: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    @ObservationIgnored private var cancellables = Set<AnyCancellable>()
    @ObservationIgnored private var canReuseSessionForReauthentication = false
    @ObservationIgnored private var countryLoadTask: Task<Void, Never>?
    @ObservationIgnored private var databaseExistedBeforeStart = false
    @ObservationIgnored private var messageSubscription: AnyCancellable?
    @ObservationIgnored private var loadingCapabilityMessageIds = Set<Int64>()
    @ObservationIgnored private var loadingReplyContextMessageIds = Set<Int64>()
    @ObservationIgnored private var loadingServiceMessageIds = Set<Int64>()
    @ObservationIgnored private var loadingForwardedMessageIds = Set<Int64>()
    @ObservationIgnored private var senderNameRequests = [MacMessageSenderKey: Task<String?, Never>]()
    @ObservationIgnored private var senderNamesByKey = [MacMessageSenderKey: String]()
    @ObservationIgnored private var openTask: Task<Void, Never>?
    @ObservationIgnored private var documentPaths = [Int: String]()
    @ObservationIgnored private var photoPaths = [Int: String]()
    @ObservationIgnored private var preferredCountryId: String?
    @ObservationIgnored private var videoPaths = [Int: String]()
    @ObservationIgnored private var recordingTimer: Task<Void, Never>?
    @ObservationIgnored private let notifications = MacLocalNotifications()
    @ObservationIgnored private var pushNotifications: TelegramApplePushRegistration
    @ObservationIgnored private var session: TelegramSession
    @ObservationIgnored private var isStopping = false
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

    private func sendTextMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let openedChatId, !text.isEmpty else { return }
        let replyTo = TelegramMessageSending.replyTo(messageId: replyingToMessage?.id)
        messageText = ""
        replyingToMessage = nil
        Task {
            do {
                let formattedText = await TelegramTextFormatting.addingAutomaticEntities(
                    service: service,
                    to: FormattedText(entities: [], text: text),
                )
                try await TelegramMessageSending.send(
                    service: service,
                    chatId: openedChatId,
                    contents: [TelegramMessageSending.textContent(formattedText)],
                    replyTo: replyTo,
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
        let replyTo = TelegramMessageSending.replyTo(messageId: replyingToMessage?.id)
        let photos = urls.compactMap { url -> (URL, CGSize)? in
            guard let size = imagePixelSize(at: url), size.width > 0, size.height > 0 else { return nil }
            return (url, size)
        }
        guard !photos.isEmpty else {
            messageActionError = "The selected files could not be read as photos."
            return
        }

        selectedPhotoURLs = []
        messageText = ""
        replyingToMessage = nil
        Task {
            do {
                let formattedCaption = await TelegramTextFormatting.addingAutomaticEntities(
                    service: service,
                    to: FormattedText(entities: [], text: caption),
                )
                let contents = photos.map { url, size in
                    TelegramMessageSending.photoContent(
                        url: url,
                        caption: formattedCaption,
                        width: Int(size.width),
                        height: Int(size.height),
                    )
                }
                try await TelegramMessageSending.send(
                    service: service,
                    chatId: chatId,
                    contents: contents,
                    replyTo: replyTo,
                    uploadAction: .chatActionUploadingPhoto(.init(progress: 0)),
                )
            } catch {
                messageActionError = error.localizedDescription
            }
        }
    }

    private func sendSelectedDocuments() {
        guard let chatId = openedChatId, !selectedDocumentURLs.isEmpty else { return }
        let caption = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        let replyTo = TelegramMessageSending.replyTo(messageId: replyingToMessage?.id)
        let urls = selectedDocumentURLs

        selectedDocumentURLs = []
        messageText = ""
        replyingToMessage = nil
        Task {
            do {
                let formattedCaption = await TelegramTextFormatting.addingAutomaticEntities(
                    service: service,
                    to: FormattedText(entities: [], text: caption),
                )
                let contents = urls.map { url in
                    TelegramMessageSending.documentContent(url: url, caption: formattedCaption)
                }
                try await TelegramMessageSending.send(
                    service: service,
                    chatId: chatId,
                    contents: contents,
                    replyTo: replyTo,
                    uploadAction: .chatActionUploadingDocument(.init(progress: 0)),
                )
            } catch {
                messageActionError = error.localizedDescription
            }
        }
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

    private func handleMessageSnapshot(_ snapshot: TelegramMessageSnapshot) {
        messages = displayedMessageSnapshot(snapshot)
        switch snapshot.change {
        case .newMessage(let update) where !update.message.isOutgoing:
            let isMuted = (chatList.items[snapshot.chatId]?.notificationSettings?.muteFor ?? 0) > 0
            MacServiceSoundManager.shared.playIncomingMessageIfAppropriate(isMuted: isMuted)
        case .messageSendSucceeded(let update) where update.message.isOutgoing:
            MacServiceSoundManager.shared.playMessageDelivered()
        default:
            break
        }

        // The four cases below all now carry enough state in their own update payload for
        // `TelegramMessageStore.reduce(_:)` to patch its cached `Message` directly (see
        // `Message.applying`), so `messages` above already reflects the change - no need to
        // round-trip a `getMessage` RPC here just to pick it up. Only the message's cached
        // capabilities (edit/pin/reaction permissions) still need invalidating, since those
        // aren't part of `Message` itself.
        let messageId: Int64? =
            switch snapshot.change {
            case .messageContentChanged(let update):
                update.messageId
            case .messageEdited(let update):
                update.messageId
            case .messageInteractionInfo(let update):
                update.messageId
            case .messagePinChanged(let update):
                update.messageId
            default:
                nil
            }
        guard let messageId else { return }
        messageCapabilities[messageId] = nil
    }

    /// The shared store intentionally retains a larger scrollback cache, but handing all of it to
    /// AppKit on every reopen makes NSTableView synchronously rebuild and measure hundreds of
    /// hosted SwiftUI rows. macOS presents only a small window and expands it when the user reaches
    /// the top; the store remains unchanged, so older messages are still immediately available.
    private func displayedMessageSnapshot(_ snapshot: TelegramMessageSnapshot) -> TelegramMessageSnapshot {
        guard snapshot.orderedMessageIds.count > displayedMessageLimit else { return snapshot }

        let visibleRange: Range<Int>
        if let anchorId = displayedMessageAnchorId,
           let anchorIndex = snapshot.orderedMessageIds.firstIndex(of: anchorId)
        {
            let tentativeLowerBound = max(0, anchorIndex - displayedMessageLimit / 2)
            let upperBound = min(snapshot.orderedMessageIds.count, tentativeLowerBound + displayedMessageLimit)
            let lowerBound = max(0, upperBound - displayedMessageLimit)
            visibleRange = lowerBound..<upperBound
        } else {
            let lowerBound = snapshot.orderedMessageIds.count - displayedMessageLimit
            visibleRange = lowerBound..<snapshot.orderedMessageIds.count
        }

        let visibleIds = Array(snapshot.orderedMessageIds[visibleRange])
        let visibleMessages = Dictionary(uniqueKeysWithValues: visibleIds.compactMap { messageId in
            snapshot.messages[messageId].map { (messageId, $0) }
        })
        return TelegramMessageSnapshot(
            chatId: snapshot.chatId,
            version: snapshot.version,
            messages: visibleMessages,
            orderedMessageIds: visibleIds,
            unreadCount: snapshot.unreadCount,
            hasMergedHistory: snapshot.hasMergedHistory,
            change: snapshot.change,
        )
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
                self?.handleConversationHeaderUpdate(update)
            }
            .store(in: &cancellables)
    }

    private func applyAuthorizationState(_ state: AuthorizationState) {
        authorizationState = state
        authorizationStatus = Self.title(for: state)
        switch state {
        case .authorizationStateWaitPhoneNumber:
            loadCountriesIfNeeded()
            let defaults = UserDefaults.standard
            let hasAuthorizationHistory = defaults.object(forKey: Self.authorizationHistoryDefaultsKey) != nil
            let isExistingDatabaseMigration = Self.databaseDirectoryName == "td"
                && !hasAuthorizationHistory
                && databaseExistedBeforeStart
            defaults.set(true, forKey: Self.authorizationHistoryDefaultsKey)
            if !isStopping,
               defaults.bool(forKey: Self.wasAuthorizedDefaultsKey) || isExistingDatabaseMigration
            {
                canReuseSessionForReauthentication = true
                sessionEnded = true
                canReauthenticate = true
            }
        case .authorizationStateReady:
            UserDefaults.standard.set(true, forKey: Self.authorizationHistoryDefaultsKey)
            UserDefaults.standard.set(true, forKey: Self.wasAuthorizedDefaultsKey)
            canReuseSessionForReauthentication = false
            sessionEnded = false
            canReauthenticate = false
            bootstrapChats()
            Task {
                guard await notifications.requestAuthorization() else { return }
                NSApplication.shared.registerForRemoteNotifications()
            }
        case .authorizationStateClosing, .authorizationStateLoggingOut:
            guard !isStopping else { return }
            canReuseSessionForReauthentication = false
            sessionEnded = true
            canReauthenticate = false
        case .authorizationStateClosed:
            guard !isStopping else { return }
            canReuseSessionForReauthentication = false
            sessionEnded = true
            canReauthenticate = true
        default:
            break
        }
    }

    private func cancelWorkForSessionReplacement() {
        cancelVoiceRecording()
        historyRequestGeneration &+= 1
        openTask?.cancel()
        openTask = nil
        bootstrapTask?.cancel()
        bootstrapTask = nil
        searchTask?.cancel()
        searchTask = nil
        countryLoadTask?.cancel()
        countryLoadTask = nil
        conversationHeaderTask?.cancel()
        conversationHeaderTask = nil
        messageSubscription?.cancel()
        messageSubscription = nil
        for request in senderNameRequests.values {
            request.cancel()
        }
        senderNameRequests = [:]
        cancellables.removeAll()

        chatList = .empty
        selectedChatFolderId = .main
        focusedChatId = nil
        openedChatId = nil
        openedChatType = nil
        conversationHeaderBaseStatus = nil
        conversationHeaderActivities = [:]
        messages = .empty(chatId: 0)
        loadedChatFolderIds = []
        messageText = ""
        editMessageText = ""
        editingMessage = nil
        replyingToMessage = nil
        messageCapabilities = [:]
        messageReplyContexts = [:]
        messageForwardedFrom = [:]
        messageSenderNames = [:]
        messageServiceDescriptions = [:]
        selectedDocumentURLs = []
        selectedPhotoURLs = []
        phoneNumber = ""
        loginCode = ""
        password = ""
        loginError = nil
        isLoadingChats = false
        isLoadingMessages = false
        isLoadingOlderMessages = false
        isLoadingLatestMessages = false
    }

    private func loadCountriesIfNeeded() {
        guard countryNumbers.isEmpty, countryLoadTask == nil else { return }
        countryLoadTask = Task { [weak self] in
            guard let self else { return }
            defer { countryLoadTask = nil }
            async let countriesResult = try? service.getCountries()
            async let countryCodeResult = try? service.getCountryCode()
            let countries = await countriesResult?.countries ?? []
            let currentCountryCode = await countryCodeResult?.text
            guard !Task.isCancelled else { return }

            let numbers = TelegramPhoneNumber.countries(from: countries)
            countryNumbers = numbers
            if callingCode.isEmpty,
               let current = TelegramPhoneNumber.country(for: currentCountryCode, in: numbers)
            {
                selectCountry(current)
            } else if callingCode.isEmpty {
                selectedCountryNumber = nil
            } else {
                updateCallingCode(callingCode)
            }
        }
    }

    private func handleNotificationUpdate(_ update: Update) {
        guard case .updateNotificationGroup(let group) = update else { return }

        notifications.remove(
            notificationGroupId: group.notificationGroupId,
            notificationIds: group.removedNotificationIds,
        )

        guard openedChatId != group.chatId || !NSApplication.shared.isActive else { return }
        let title = chatList.items[group.chatId]?.title ?? "BetterTG"
        for notification in group.addedNotifications {
            guard Date().timeIntervalSince1970 - TimeInterval(notification.date) < 3600,
                  let body = notificationBody(notification)
            else { continue }
            let playsSound = group.notificationSoundId != 0 && !notification.isSilent
            Task {
                await notifications.deliver(
                    chatId: group.chatId,
                    title: title,
                    body: body,
                    notificationGroupId: group.notificationGroupId,
                    notificationId: notification.id,
                    playsSound: playsSound,
                )
            }
        }
    }

    private func notificationBody(_ notification: TDLibKit.Notification) -> String? {
        switch notification.type {
        case .notificationTypeNewMessage(let value):
            guard !value.message.isOutgoing else { return nil }
            return value.showPreview ? macMessageText(value.message) : "You have a new message."
        case .notificationTypeNewPushMessage(let value):
            guard !value.isOutgoing else { return nil }
            return value.senderName.isEmpty ? "You have a new message." : "New message from \(value.senderName)."
        case .notificationTypeNewCall, .notificationTypeNewSecretChat:
            return nil
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
