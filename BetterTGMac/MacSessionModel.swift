// MacSessionModel.swift

import AppKit
import AVFoundation
import Combine
import Foundation
import SwiftUI
import TDLibKit
import UniformTypeIdentifiers

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
        self.conversationSearch = TelegramConversationSearchStore(service: session)
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
    var messageTranslations = [Int64: FormattedText]()
    var translationShownMessageIds = Set<Int64>()
    var translatingMessageIds = Set<Int64>()
    /// Cached once per message via `loadTranslationEligibility(for:)`, not recomputed on every
    /// render - language detection runs an on-device ML model (`NLLanguageRecognizer`), too
    /// expensive to call from a plain computed property SwiftUI might re-evaluate per re-render.
    var messageTranslationEligibility = [Int64: Bool]()
    var detectedChatLanguage: String?
    var isChatTranslationEnabled = false
    var messageActionError: String?
    var isAddingContact = false
    var isSubmittingMessage = false
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
    var pinnedMessages = [Message]()
    var isLoadingPinnedMessages = false
    var pinnedMessagesError: String?
    var scheduledMessages = [Message]()
    var isLoadingScheduledMessages = false
    var scheduledMessagesError: String?
    var navigationTargetMessageId: Int64?
    var latestHistoryTargetMessageId: Int64?
    var openedUnreadCount = 0
    var openedLastReadInboxMessageId: Int64 = 0
    var conversationHeaderBaseStatus: String?
    var conversationHeaderActivities = [MessageSender: ChatAction]()

    let linkPreviewComposer: TelegramLinkPreviewComposer
    let editLinkPreviewComposer: TelegramLinkPreviewComposer
    let conversationSearch: TelegramConversationSearchStore

    @ObservationIgnored var bootstrapTask: Task<Void, Never>?
    @ObservationIgnored var loadedChatFolderIds = Set<MacChatFolderID>()
    @ObservationIgnored var searchTask: Task<Void, Never>?
    @ObservationIgnored var searchGeneration: UInt64 = 0
    @ObservationIgnored var pinnedMessagesTask: Task<Void, Never>?
    @ObservationIgnored var pinnedMessagesGeneration: UInt64 = 0
    @ObservationIgnored var scheduledMessagesTask: Task<Void, Never>?
    @ObservationIgnored var scheduledMessagesGeneration: UInt64 = 0
    @ObservationIgnored var historyRequestGeneration: UInt64 = 0
    @ObservationIgnored var service: any TelegramService
    @ObservationIgnored var draftReplyLoadTask: Task<Void, Never>?

    @ObservationIgnored var conversationHeaderTask: Task<Void, Never>?
    @ObservationIgnored var openedChatType: ChatType?

    // The following were `private` while every method that used them lived in this same file.
    // They're now shared across the `MacSessionModel+*.swift` extension files below, so they need
    // at least internal access - `private` is scoped to the declaring file, not the type, and
    // extensions in other files can't add stored properties of their own to reach for instead.
    @ObservationIgnored var countryLoadTask: Task<Void, Never>?
    @ObservationIgnored var messageSubscription: AnyCancellable?
    @ObservationIgnored var loadingCapabilityMessageIds = Set<Int64>()
    @ObservationIgnored var loadingReactionMessageIds = Set<Int64>()
    @ObservationIgnored var loadingReplyContextMessageIds = Set<Int64>()
    @ObservationIgnored var loadingServiceMessageIds = Set<Int64>()
    @ObservationIgnored var loadingForwardedMessageIds = Set<Int64>()
    @ObservationIgnored var senderNameRequests = [MacMessageSenderKey: Task<String?, Never>]()
    @ObservationIgnored var senderNamesByKey = [MacMessageSenderKey: String]()
    @ObservationIgnored var openTask: Task<Void, Never>?
    @ObservationIgnored var localFilePaths = [Int: String]()
    @ObservationIgnored var preferredCountryId: String?
    @ObservationIgnored var recordingTimer: Task<Void, Never>?
    @ObservationIgnored let notifications = MacLocalNotifications()
    @ObservationIgnored var voiceRecorder: VoiceNoteRecorder?
    @ObservationIgnored var voiceRecordingChatId: Int64?
    @ObservationIgnored var voiceRecordingStartedAt: Foundation.Date?
    @ObservationIgnored var voiceRecordingURL: URL?
    @ObservationIgnored var voiceRecordingWave = [Float]()

    var messageText = NSAttributedString(string: "") {
        didSet { linkPreviewComposer.update(text: macComposerFormattedText(messageText)) }
    }

    var editMessageText = NSAttributedString(string: "") {
        didSet { editLinkPreviewComposer.update(text: macComposerFormattedText(editMessageText)) }
    }

    var formattedPhoneNumber: String {
        TelegramPhoneNumber.display(callingCode: callingCode, number: phoneNumber)
    }

    var expectedLoginCodeLength: Int? {
        guard case .authorizationStateWaitCode(let details) = authorizationState else { return nil }
        return details.codeInfo.type.expectedLength
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
        conversationSearch.replaceService(replacementSession)
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
    @ObservationIgnored private var databaseExistedBeforeStart = false
    @ObservationIgnored private var pushNotifications: TelegramApplePushRegistration
    @ObservationIgnored private var session: TelegramSession
    @ObservationIgnored private var isStopping = false
    @ObservationIgnored private var started = false

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
        scheduledMessagesTask?.cancel()
        scheduledMessagesTask = nil
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
        scheduledMessages = []
        scheduledMessagesError = nil
        isLoadingPinnedMessages = false
        messages = .empty(chatId: 0)
        loadedChatFolderIds = []
        messageText = NSAttributedString(string: "")
        editMessageText = NSAttributedString(string: "")
        editingMessage = nil
        replyingToMessage = nil
        messageCapabilities = [:]
        messageAvailableReactions = [:]
        messageReplyContexts = [:]
        messageForwardedFrom = [:]
        messageSenderNames = [:]
        messageServiceDescriptions = [:]
        messageTranslations = [:]
        translationShownMessageIds = []
        translatingMessageIds = []
        messageTranslationEligibility = [:]
        detectedChatLanguage = nil
        isChatTranslationEnabled = false
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
}
