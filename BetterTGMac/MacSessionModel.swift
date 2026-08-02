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

/// Keep TDLib's high-volume update stream off the main queue unless the macOS presentation model
/// actually consumes the update. Cold chats can emit many file-progress and synchronization
/// updates; scheduling those no-op events on MainActor can starve AppKit input handling.
private func isMacSessionPresentationUpdate(_ update: Update) -> Bool {
    switch update {
    case .updateBasicGroup,
         .updateBasicGroupFullInfo,
         .updateChatAction,
         .updateNotificationGroup,
         .updateSupergroup,
         .updateSupergroupFullInfo,
         .updateUser,
         .updateUserStatus:
        true
    default:
        false
    }
}

// MARK: - MacSessionModel

@MainActor @Observable final class MacSessionModel {
    // MARK: Lifecycle

    init() {
        let session = TelegramSession()
        self.session = session
        self.service = session
        self.linkPreviewComposer = TelegramLinkPreviewComposer(service: session)
        self.editLinkPreviewComposer = TelegramLinkPreviewComposer(service: session)
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
    var editingMessage: Message?
    var replyingToMessage: Message?
    var messageCapabilities = [Int64: MacMessageCapabilities]()
    var messageAvailableReactions = [Int64: [AvailableReaction]]()
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
    var isConversationSearchActive = false
    var isSearchingConversation = false
    var conversationSearchQuery = ""
    var conversationSearchResultIds = [Int64]()
    var conversationSearchSelectedIndex: Int?
    var conversationSearchTotalCount = 0
    var conversationSearchError: String?
    var pinnedMessages = [Message]()
    var isLoadingPinnedMessages = false
    var pinnedMessagesError: String?
    var navigationTargetMessageId: Int64?
    var latestHistoryTargetMessageId: Int64?
    var openedUnreadCount = 0
    var openedLastReadInboxMessageId: Int64 = 0
    var conversationHeaderBaseStatus: String?
    var conversationHeaderActivities = [MessageSender: ChatAction]()

    let linkPreviewComposer: TelegramLinkPreviewComposer
    let editLinkPreviewComposer: TelegramLinkPreviewComposer

    @ObservationIgnored var bootstrapTask: Task<Void, Never>?
    @ObservationIgnored var loadedChatFolderIds = Set<MacChatFolderID>()
    @ObservationIgnored var searchTask: Task<Void, Never>?
    @ObservationIgnored var searchGeneration: UInt64 = 0
    @ObservationIgnored var conversationSearchTask: Task<Void, Never>?
    @ObservationIgnored var conversationSearchGeneration: UInt64 = 0
    @ObservationIgnored var conversationSearchNextFromMessageId: Int64 = 0
    @ObservationIgnored var conversationSearchNextOffset = ""
    @ObservationIgnored var conversationSearchUsesSecretMessages = false
    @ObservationIgnored var pinnedMessagesTask: Task<Void, Never>?
    @ObservationIgnored var pinnedMessagesGeneration: UInt64 = 0
    @ObservationIgnored var historyRequestGeneration: UInt64 = 0
    @ObservationIgnored var service: any TelegramService
    @ObservationIgnored var draftReplyLoadTask: Task<Void, Never>?

    @ObservationIgnored var conversationHeaderTask: Task<Void, Never>?
    @ObservationIgnored var openedChatType: ChatType?

    var messageText = "" {
        didSet { linkPreviewComposer.update(text: FormattedText(entities: [], text: messageText)) }
    }

    var editMessageText = "" {
        didSet { editLinkPreviewComposer.update(text: FormattedText(entities: [], text: editMessageText)) }
    }

    var activeLinkPreviewComposer: TelegramLinkPreviewComposer {
        editingMessage == nil ? linkPreviewComposer : editLinkPreviewComposer
    }

    var chatItems: [ChatListItemState] {
        chatList.chatIds(in: selectedChatList).compactMap { chatList.items[$0] }
    }

    /// All chats across the main list and archive, regardless of which sidebar folder is currently
    /// selected - used by the forward picker, which shouldn't be scoped to `selectedChatList`.
    var allChatItems: [ChatListItemState] {
        let ids = chatList.chatIds(in: .chatListMain) + chatList.chatIds(in: .chatListArchive)
        return ids.compactMap { chatList.items[$0] }
    }

    var formattedPhoneNumber: String {
        TelegramPhoneNumber.display(callingCode: callingCode, number: phoneNumber)
    }

    var expectedLoginCodeLength: Int? {
        guard case .authorizationStateWaitCode(let details) = authorizationState else { return nil }
        return details.codeInfo.type.expectedLength
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
        if openedChatId != chatId, isConversationSearchActive {
            endConversationSearch()
        }

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

        saveCurrentDraft()
        let openingChat = chatList.items[chatId]
        openedUnreadCount = openingChat?.unreadCount ?? 0
        openedLastReadInboxMessageId = openingChat?.lastReadInboxMessageId ?? 0

        cancelVoiceRecording()
        selectedPhotoURLs = []
        selectedDocumentURLs = []

        let previousChatId = openedChatId
        openedChatId = chatId
        pinnedMessages = []
        pinnedMessagesError = nil
        refreshPinnedMessages(for: chatId)
        restoreDraft(openingChat?.draftMessage, chatId: chatId)
        prepareConversationHeader(for: chatId, fallbackKind: openingChat?.kind)
        messages = .empty(chatId: chatId)
        editingMessage = nil
        replyingToMessage = nil
        editMessageText = ""
        messageCapabilities = [:]
        messageAvailableReactions = [:]
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
                Task { _ = try? await self.service.closeChat(chatId: previousChatId) }
            }
            guard !Task.isCancelled, openedChatId == chatId else { return }
            _ = try? await service.openChat(chatId: chatId)
            let historyMessages: [Message] =
                if messageId == nil,
                messages.hasMergedHistory,
                !messages.orderedMessageIds.isEmpty {
                    // The subscription already delivered this chat's retained history. Fetching and
                    // merging the same page again only increments the snapshot version and forces a
                    // second table refresh immediately after the cached rows became visible.
                    messages.orderedMessageIds.compactMap { self.messages.messages[$0] }
                } else {
                    await loadInitialHistory(chatId: chatId, around: messageId)
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

    @discardableResult func attachPastedFiles(_ urls: [URL]) -> Bool {
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
        voiceRecordingWave = []
        isRecordingVoice = true
        recordingTimer?.cancel()
        recordingTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard let self, isRecordingVoice, let startedAt = voiceRecordingStartedAt else { return }
                voiceRecordingDuration = Foundation.Date().timeIntervalSince(startedAt)
                voiceRecordingWave.append(voiceRecorder?.peakPower ?? -160)
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

        let waveform = TelegramVoiceNoteSending.waveform(from: voiceRecordingWave)
        let replyTo = TelegramMessageSending.replyTo(messageId: replyingToMessage?.id)
        clearDraft(chatId: chatId)
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
                    waveform: waveform,
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

    func localStickerPath(fileId: Int) async -> String? {
        if let cachedPath = stickerPaths[fileId] {
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
        stickerPaths[fileId] = file.local.path
        return file.local.path
    }

    func beginReply(to message: Message) {
        draftReplyLoadTask?.cancel()
        draftReplyLoadTask = nil
        editingMessage = nil
        editMessageText = ""
        replyingToMessage = message
    }

    func cancelReplyOrEdit() {
        draftReplyLoadTask?.cancel()
        draftReplyLoadTask = nil
        editingMessage = nil
        replyingToMessage = nil
        editMessageText = ""
        editLinkPreviewComposer.configure(preview: nil, options: nil)
    }

    func beginEditing(_ message: Message) {
        guard let text = TelegramMessageEditing.editableFormattedText(from: message)?.text else { return }
        selectedPhotoURLs = []
        selectedDocumentURLs = []
        replyingToMessage = nil
        editLinkPreviewComposer.configure(
            preview: telegramMessageLinkPreview(message),
            options: telegramMessageLinkPreviewOptions(message),
        )
        editingMessage = message
        editMessageText = text
    }

    @discardableResult func forward(_ message: Message, to chatId: Int64) async -> Bool {
        do {
            try await TelegramMessageActions.forward(
                service: service,
                messageIds: [message.id],
                fromChatId: message.chatId,
                toChatId: chatId,
            )
            return true
        } catch {
            return false
        }
    }

    /// Forwards to every chat concurrently rather than one at a time, so picking several
    /// destinations doesn't make the last one wait on all the earlier round trips.
    @discardableResult func forward(_ message: Message, to chatIds: [Int64]) async -> Bool {
        let succeededCount = await withTaskGroup(of: Bool.self) { group in
            for chatId in chatIds {
                group.addTask { await self.forward(message, to: chatId) }
            }
            return await group.reduce(into: 0) { count, succeeded in count += succeeded ? 1 : 0 }
        }
        if succeededCount < chatIds.count {
            messageActionError = succeededCount == 0
                ? "This message couldn't be forwarded."
                : "The message couldn't be forwarded to all the selected chats."
        }
        return succeededCount == chatIds.count
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
        ), openedChatId == message.chatId
        else { return }

        messageCapabilities[message.id] = MacMessageCapabilities(
            properties: properties,
        )
    }

    func loadAvailableReactions(for message: Message) async {
        guard messageAvailableReactions[message.id] == nil,
              !loadingReactionMessageIds.contains(message.id),
              openedChatId == message.chatId
        else { return }
        loadingReactionMessageIds.insert(message.id)
        defer { loadingReactionMessageIds.remove(message.id) }

        guard let availableReactions = try? await service.getMessageAvailableReactions(
            chatId: message.chatId,
            messageId: message.id,
            rowSize: 8,
        ),
            openedChatId == message.chatId
        else { return }
        messageAvailableReactions[message.id] = telegramAvailableReactions(availableReactions)
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
        if ownsRequest {
            senderNameRequests[resolvedSenderKey] = nil
        }
        guard let name, !name.isEmpty else { return }
        if !ownsRequest {
            guard openedChatId == message.chatId,
                  messageSenderNames[message.id] != name
            else { return }
            messageSenderNames[message.id] = name
            return
        }

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

    func saveCurrentDraft() {
        guard editingMessage == nil, let chatId = openedChatId else { return }
        let draft = TelegramDrafts.make(
            formattedText: FormattedText(entities: [], text: messageText),
            replyMessageId: replyingToMessage?.id,
            linkPreviewOptions: linkPreviewComposer.options,
        )
        let service = service
        Task {
            _ = try? await service.setChatDraftMessage(
                chatId: chatId,
                draftMessage: draft,
                topicId: nil,
            )
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
    @ObservationIgnored private var loadingReactionMessageIds = Set<Int64>()
    @ObservationIgnored private var loadingReplyContextMessageIds = Set<Int64>()
    @ObservationIgnored private var loadingServiceMessageIds = Set<Int64>()
    @ObservationIgnored private var loadingForwardedMessageIds = Set<Int64>()
    @ObservationIgnored private var senderNameRequests = [MacMessageSenderKey: Task<String?, Never>]()
    @ObservationIgnored private var senderNamesByKey = [MacMessageSenderKey: String]()
    @ObservationIgnored private var openTask: Task<Void, Never>?
    @ObservationIgnored private var documentPaths = [Int: String]()
    @ObservationIgnored private var photoPaths = [Int: String]()
    @ObservationIgnored private var stickerPaths = [Int: String]()
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
    @ObservationIgnored private var voiceRecordingWave = [Float]()

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

    private func clearDraft(chatId: Int64) {
        let service = service
        Task {
            _ = try? await service.setChatDraftMessage(
                chatId: chatId,
                draftMessage: nil,
                topicId: nil,
            )
        }
    }

    private func restoreDraft(_ draft: DraftMessage?, chatId: Int64) {
        draftReplyLoadTask?.cancel()
        draftReplyLoadTask = nil
        let linkPreviewOptions: LinkPreviewOptions? =
            if let draft, case .draftMessageContentText(let content) = draft.content {
                content.linkPreviewOptions
            } else {
                nil
            }
        linkPreviewComposer.configure(preview: nil, options: linkPreviewOptions)
        messageText = TelegramDrafts.text(from: draft)
        replyingToMessage = nil

        guard let replyMessageId = TelegramDrafts.replyMessageId(from: draft) else { return }
        let service = service
        draftReplyLoadTask = Task { [weak self] in
            let message = try? await service.getMessage(chatId: chatId, messageId: replyMessageId)
            guard !Task.isCancelled,
                  let self,
                  openedChatId == chatId,
                  replyingToMessage == nil
            else { return }
            replyingToMessage = message
            draftReplyLoadTask = nil
        }
    }

    private func sendTextMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let openedChatId, !text.isEmpty else { return }
        let replyTo = TelegramMessageSending.replyTo(messageId: replyingToMessage?.id)
        let linkPreviewOptions = linkPreviewComposer.options
        clearDraft(chatId: openedChatId)
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
                    contents: [TelegramMessageSending.textContent(
                        formattedText,
                        linkPreviewOptions: linkPreviewOptions,
                    )],
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

        clearDraft(chatId: chatId)
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

        clearDraft(chatId: chatId)
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
        voiceRecordingWave = []
        isRecordingVoice = false
    }

    private func editMessage() {
        guard let message = editingMessage else { return }
        let text = editMessageText.trimmingCharacters(in: .whitespacesAndNewlines)
        if case .messageText = message.content, text.isEmpty {
            return
        }
        let linkPreviewOptions = editLinkPreviewComposer.options
        editingMessage = nil
        editMessageText = ""

        performMessageAction {
            await TelegramMessageEditing.editMessage(
                service: self.service,
                chatId: message.chatId,
                messageId: message.id,
                messageContent: message.content,
                newText: FormattedText(entities: [], text: text),
                linkPreviewOptions: linkPreviewOptions,
            )
        }
    }

    private func handleMessageSnapshot(_ snapshot: TelegramMessageSnapshot) {
        switch snapshot.change {
        case .chatAction, .readInbox, .readOutbox, .userStatus:
            // None of these touch `messages`/`orderedMessageIds` (see `TelegramMessageStore.reduce`),
            // and nothing on macOS reads `messages.unreadCount` or `messages.change` for them - only
            // `MacMessageTable`'s `.onChange(of: model.messages.version)` does, which otherwise forces
            // a full message-list re-diff on every typing indicator, read receipt, or online-status
            // ping for the open chat. That diff is expensive enough (SwiftUI's List/OutlineListCoordinator
            // reconciliation) that a burst of these arriving right as a chat opens visibly froze the UI.
            return
        default:
            break
        }
        messages = snapshot
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
        if case .messagePinChanged = snapshot.change {
            refreshPinnedMessages()
        }
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
            // Filter on TelegramUpdateStore's background queue, before `receive(on:)` schedules
            // work on AppKit's event loop. The two handlers below ignore every other update type.
                .filter(isMacSessionPresentationUpdate)
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
        draftReplyLoadTask?.cancel()
        draftReplyLoadTask = nil
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
        pinnedMessagesTask?.cancel()
        pinnedMessagesTask = nil
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
        pinnedMessages = []
        pinnedMessagesError = nil
        isLoadingPinnedMessages = false
        messages = .empty(chatId: 0)
        loadedChatFolderIds = []
        messageText = ""
        editMessageText = ""
        editingMessage = nil
        replyingToMessage = nil
        messageCapabilities = [:]
        messageAvailableReactions = [:]
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
