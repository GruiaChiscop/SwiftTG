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

    /// Matches the first page assembled by `fetchMessagesBackward`. The shared macOS message
    /// store intentionally retains every explicitly loaded page, but mounting that entire retained
    /// history when a chat is reopened can make SwiftUI's `List` synchronously build thousands of
    /// rows. `loadedMessageIds` below keeps the presented window bounded until the user paginates.
    static let initialHistoryWindowSize = 30

    var authorizationState: AuthorizationState?
    var authorizationStatus = "Starting Telegram…"
    var sessionEnded = false
    var canReauthenticate = false
    var chatList = ChatListSnapshot.empty
    /// Cached once per chat via `loadIdentityBadge(for:)`, keyed by `chatId` - the inner `Optional`
    /// distinguishes "not loaded yet" (key absent) from "loaded, no badge" (`nil` value present).
    var chatIdentityBadges = [Int64: TelegramIdentityBadge?]()
    var selectedChatFolderId = MacChatFolderID.main
    var focusedChatId: Int64?
    var openedChatId: Int64?
    /// When set, `openedChatId` is scoped to a single forum topic or comment thread rather than
    /// the chat's whole history - `nil` preserves ordinary full-chat behavior everywhere below.
    /// Mirrors iOS's `ChatVM.messageTopic`.
    var openedTopic: MessageTopic?
    /// Display name for `openedTopic`, shown in `MacConversationHeader` instead of the parent
    /// chat's name while a forum topic is open - `nil` whenever `openedTopic` is.
    var openedTopicTitle: String?
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
    var emailAddress = ""
    var emailCode = ""
    var registrationFirstName = ""
    var registrationLastName = ""
    var registrationPhotoData: Data?
    var hasAcceptedRegistrationTerms = false
    var showsRegistrationTermsConfirmation = false
    var qrCodeLink: String?
    var isLoadingChats = false
    var isLoadingMessages = false
    var isLoadingOlderMessages = false
    var isLoadingLatestMessages = false
    var canLoadOlderMessages = true
    var isRecordingVoice = false
    var voiceRecordingDuration: TimeInterval = 0
    var searchQuery = ""
    var chatSearchResults = [MacChatSearchResult]()
    var globalChatSearchResults = [MacChatSearchResult]()
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
    var deepLinkErrorMessage: String?
    var pendingDeepLinkJoin: TelegramPendingDeepLinkJoin?

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
    @ObservationIgnored var loadedMessageIds = Set<Int64>()
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

    var expectedEmailCodeLength: Int? {
        guard case .authorizationStateWaitEmailCode(let details) = authorizationState else { return nil }
        return details.codeInfo.length > 0 ? details.codeInfo.length : nil
    }

    var emailAddressPattern: String {
        guard case .authorizationStateWaitEmailCode(let details) = authorizationState else { return "" }
        return details.codeInfo.emailAddressPattern
    }

    var registrationTermsOfService: TermsOfService? {
        guard case .authorizationStateWaitRegistration(let details) = authorizationState else { return nil }
        return details.termsOfService
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

        recreateSession()
    }

    /// Closes the current TDLib session and starts a fresh one, guaranteed to land on a clean
    /// `authorizationStateWaitPhoneNumber` regardless of the state being left behind - used by
    /// `reauthenticate()` above, and by `cancelQrCodeLogin()` (`MacSessionModel+Login.swift`) to
    /// back out of `authorizationStateWaitOtherDeviceConfirmation`, which has no direct "cancel"
    /// TDLib call of its own.
    func recreateSession() {
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

        // Nothing else updates the Dock badge - it otherwise stays wherever it last was (or
        // permanently unset), since reading messages while the app is open never touches it on
        // its own. `unreadUnmutedCount` matches the official app's own badge convention of
        // excluding muted chats.
        service.unreadChatCountPublisher
            .compactMap { $0?.unreadUnmutedCount }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { count in
                NSApp.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
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
            // Resolved eagerly so `TelegramCurrentUserCache`'s synchronous `userId` is already
            // populated by the time chat rows render, avoiding a visible name-then-"Saved
            // Messages" flash.
            Task { await TelegramCurrentUserCache.shared.userId(service: service) }
            Task {
                guard await notifications.requestAuthorization() else { return }
                NSApplication.shared.registerForRemoteNotifications()
            }
            Task { [service] in
                await TelegramNotificationSoundCacheRefresh.refreshAll(service: service)
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
        case .authorizationStateWaitEmailAddress:
            break
        case .authorizationStateWaitEmailCode:
            break
        case .authorizationStateWaitRegistration:
            hasAcceptedRegistrationTerms = false
        case .authorizationStateWaitOtherDeviceConfirmation(let details):
            qrCodeLink = details.link
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
        openedTopic = nil
        openedTopicTitle = nil
        openedChatType = nil
        conversationHeaderBaseStatus = nil
        conversationHeaderActivities = [:]
        pinnedMessages = []
        pinnedMessagesError = nil
        scheduledMessages = []
        scheduledMessagesError = nil
        isLoadingPinnedMessages = false
        messages = .empty(chatId: 0)
        loadedMessageIds = []
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
