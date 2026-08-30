// TelegramPrivacySettings.swift

import SwiftUI
@preconcurrency import TDLibKit

// MARK: - TelegramPrivacyOption

enum TelegramPrivacyOption: CaseIterable, Equatable, Identifiable {
    case everybody
    case myContacts
    case nobody

    // MARK: Lifecycle

    init(rules: UserPrivacySettingRules) {
        for rule in rules.rules {
            switch rule {
            case .userPrivacySettingRuleAllowContacts:
                self = .myContacts
                return
            case .userPrivacySettingRuleRestrictAll:
                self = .nobody
                return
            case .userPrivacySettingRuleAllowAll:
                self = .everybody
                return
            default:
                continue
            }
        }
        self = .everybody
    }

    // MARK: Internal

    var id: Self { self }

    var title: String {
        switch self {
        case .everybody: "Everybody"
        case .myContacts: "My Contacts"
        case .nobody: "Nobody"
        }
    }

    // MARK: Fileprivate

    fileprivate var baseRules: [UserPrivacySettingRule] {
        switch self {
        case .everybody: [.userPrivacySettingRuleAllowAll]
        case .myContacts: [.userPrivacySettingRuleAllowContacts, .userPrivacySettingRuleRestrictAll]
        case .nobody: [.userPrivacySettingRuleRestrictAll]
        }
    }
}

// MARK: - TelegramPrivacyRules

/// Edits the rules SwiftTG understands without discarding TDLib rules added by other clients.
/// User-specific rules must precede broader contact/all rules because TDLib uses the first match.
enum TelegramPrivacyRules {
    static func alwaysAllowUserIds(in rules: UserPrivacySettingRules) -> Set<Int64> {
        Set(rules.rules.flatMap { rule -> [Int64] in
            guard case .userPrivacySettingRuleAllowUsers(let value) = rule else { return [] }
            return value.userIds
        })
    }

    static func neverAllowUserIds(in rules: UserPrivacySettingRules) -> Set<Int64> {
        Set(rules.rules.flatMap { rule -> [Int64] in
            guard case .userPrivacySettingRuleRestrictUsers(let value) = rule else { return [] }
            return value.userIds
        })
    }

    static func alwaysAllowChatIds(in rules: UserPrivacySettingRules) -> Set<Int64> {
        Set(rules.rules.flatMap { rule -> [Int64] in
            guard case .userPrivacySettingRuleAllowChatMembers(let value) = rule else { return [] }
            return value.chatIds
        })
    }

    static func neverAllowChatIds(in rules: UserPrivacySettingRules) -> Set<Int64> {
        Set(rules.rules.flatMap { rule -> [Int64] in
            guard case .userPrivacySettingRuleRestrictChatMembers(let value) = rule else { return [] }
            return value.chatIds
        })
    }

    static func replacingBaseOption(
        in rules: UserPrivacySettingRules,
        with option: TelegramPrivacyOption,
    ) -> UserPrivacySettingRules {
        replacingUserExceptions(
            in: rules,
            option: option,
            alwaysAllow: alwaysAllowUserIds(in: rules),
            neverAllow: neverAllowUserIds(in: rules),
            alwaysAllowChatIds: alwaysAllowChatIds(in: rules),
            neverAllowChatIds: neverAllowChatIds(in: rules),
        )
    }

    static func replacingUserExceptions(
        in rules: UserPrivacySettingRules,
        option: TelegramPrivacyOption? = nil,
        alwaysAllow: Set<Int64>,
        neverAllow: Set<Int64>,
        alwaysAllowChatIds: Set<Int64>? = nil,
        neverAllowChatIds: Set<Int64>? = nil,
    ) -> UserPrivacySettingRules {
        let resolvedOption = option ?? TelegramPrivacyOption(rules: rules)
        let disjointNeverAllow = neverAllow.subtracting(alwaysAllow)
        let resolvedAlwaysAllowChatIds = alwaysAllowChatIds ?? self.alwaysAllowChatIds(in: rules)
        let resolvedNeverAllowChatIds = (neverAllowChatIds ?? self.neverAllowChatIds(in: rules))
            .subtracting(resolvedAlwaysAllowChatIds)
        var updatedRules = [UserPrivacySettingRule]()

        if !alwaysAllow.isEmpty {
            updatedRules.append(.userPrivacySettingRuleAllowUsers(
                UserPrivacySettingRuleAllowUsers(userIds: alwaysAllow.sorted()),
            ))
        }
        if !disjointNeverAllow.isEmpty {
            updatedRules.append(.userPrivacySettingRuleRestrictUsers(
                UserPrivacySettingRuleRestrictUsers(userIds: disjointNeverAllow.sorted()),
            ))
        }
        if !resolvedAlwaysAllowChatIds.isEmpty {
            updatedRules.append(.userPrivacySettingRuleAllowChatMembers(
                UserPrivacySettingRuleAllowChatMembers(chatIds: resolvedAlwaysAllowChatIds.sorted()),
            ))
        }
        if !resolvedNeverAllowChatIds.isEmpty {
            updatedRules.append(.userPrivacySettingRuleRestrictChatMembers(
                UserPrivacySettingRuleRestrictChatMembers(chatIds: resolvedNeverAllowChatIds.sorted()),
            ))
        }

        // Keep group, Premium, bot and "restrict contacts" exceptions in their original order.
        // SwiftTG doesn't expose editors for all of them yet (TelegramPrivacyOption has no case that
        // regenerates userPrivacySettingRuleRestrictContacts), but changing the base option or users
        // must not erase them - so anything we don't explicitly regenerate below stays untouched.
        updatedRules.append(contentsOf: rules.rules.filter { rule in
            switch rule {
            case .userPrivacySettingRuleAllowAll,
                 .userPrivacySettingRuleAllowChatMembers,
                 .userPrivacySettingRuleAllowContacts,
                 .userPrivacySettingRuleAllowUsers,
                 .userPrivacySettingRuleRestrictAll,
                 .userPrivacySettingRuleRestrictChatMembers,
                 .userPrivacySettingRuleRestrictUsers:
                false
            default:
                true
            }
        })
        updatedRules.append(contentsOf: resolvedOption.baseRules)
        return UserPrivacySettingRules(rules: updatedRules)
    }
}

// MARK: - TelegramPrivacyItem

struct TelegramPrivacyItem: Identifiable {
    let setting: UserPrivacySetting
    let title: String
    let footer: String?
    var availableOptions = TelegramPrivacyOption.allCases

    var id: String { title }
}

let telegramPrivacyItems: [TelegramPrivacyItem] = [
    TelegramPrivacyItem(setting: .userPrivacySettingShowPhoneNumber, title: "Phone Number", footer: nil),
    TelegramPrivacyItem(setting: .userPrivacySettingShowStatus, title: "Last Seen & Online", footer: nil),
    TelegramPrivacyItem(setting: .userPrivacySettingShowProfilePhoto, title: "Profile Photo", footer: nil),
    TelegramPrivacyItem(setting: .userPrivacySettingShowBio, title: "Bio", footer: nil),
    TelegramPrivacyItem(setting: .userPrivacySettingAutosaveGifts, title: "Gifts", footer: nil),
    TelegramPrivacyItem(setting: .userPrivacySettingShowBirthdate, title: "Birthday", footer: nil),
    TelegramPrivacyItem(setting: .userPrivacySettingShowProfileAudio, title: "Saved Music", footer: nil),
    TelegramPrivacyItem(
        setting: .userPrivacySettingShowLinkInForwardedMessages,
        title: "Forwarded Messages",
        footer: "When forwarded to other chats, messages you send will not link back to your account.",
    ),
    TelegramPrivacyItem(setting: .userPrivacySettingAllowCalls, title: "Calls", footer: nil),
    TelegramPrivacyItem(
        setting: .userPrivacySettingAllowPrivateVoiceAndVideoNoteMessages,
        title: "Voice & Video Messages",
        footer: nil,
    ),
    TelegramPrivacyItem(setting: .userPrivacySettingAllowChatInvites, title: "Groups & Channels", footer: nil),
]

// MARK: - TelegramAutoDeleteDuration

/// TDLib requires the auto-delete time to be a whole number of days (divisible by 86400, up to a
/// year) - these four map directly to the options the official app itself offers.
enum TelegramAutoDeleteDuration: Int, CaseIterable, Identifiable {
    case off = 0
    case oneDay = 86400
    case oneWeek = 604_800
    case oneMonth = 2_592_000

    // MARK: Lifecycle

    init(seconds: Int) {
        self = Self(rawValue: seconds) ?? .off
    }

    // MARK: Internal

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .off: "Off"
        case .oneDay: "1 Day"
        case .oneWeek: "1 Week"
        case .oneMonth: "1 Month"
        }
    }
}

// MARK: - TelegramAccountDeletionPeriod

enum TelegramAccountDeletionPeriod: Int, CaseIterable, Identifiable {
    case oneMonth = 30
    case threeMonths = 90
    case sixMonths = 180
    case oneYear = 365
    case eighteenMonths = 548
    case twoYears = 730

    // MARK: Lifecycle

    init(days: Int) {
        self = Self.allCases.min(by: { abs($0.rawValue - days) < abs($1.rawValue - days) }) ?? .sixMonths
    }

    // MARK: Internal

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .oneMonth: "1 Month"
        case .threeMonths: "3 Months"
        case .sixMonths: "6 Months"
        case .oneYear: "1 Year"
        case .eighteenMonths: "18 Months"
        case .twoYears: "2 Years"
        }
    }
}

// MARK: - TelegramPrivacyView

struct TelegramPrivacyView: View {
    // MARK: Lifecycle

    init(service: any TelegramService) {
        self.service = service
    }

    // MARK: Internal

    var body: some View {
        // Rows are plain Buttons presenting a sheet, not NavigationLinks - on macOS, a
        // List/NavigationLink placed in a NavigationSplitView's detail column (as this view is,
        // from MacSettingsView's sidebar) auto-selects and auto-pushes its first row as soon as
        // the list appears, trapping VoiceOver focus on "Last Seen & Online" with no way to reach
        // the other rows (confirmed: wrapping in a dedicated NavigationStack did not fix it - the
        // auto-select is coming from the List/NavigationSplitView column-selection interaction
        // itself, not from a missing navigation context). A sheet sidesteps that whole mechanism.
        List {
            Section {
                #if os(iOS)
                    NavigationLink {
                        BlockedUsersView(service: service)
                    } label: {
                        Label("Blocked Users", systemImage: "hand.raised.slash")
                    }

                    if connectedWebsiteCount > 0 {
                        NavigationLink {
                            TelegramWebSessionsView(service: service) { connectedWebsiteCount = $0 }
                        } label: {
                            LabeledContent("Web Sessions", value: String(connectedWebsiteCount))
                        }
                    }

                    NavigationLink {
                        TelegramAppLockSettingsView()
                    } label: {
                        Label("App Lock", systemImage: "lock")
                    }

                    NavigationLink {
                        TelegramTwoStepVerificationView(service: service)
                    } label: {
                        Label("Two-Step Verification", systemImage: "lock.shield")
                    }

                    NavigationLink {
                        TelegramPasskeysView(service: service) { passkeyCount = $0 }
                    } label: {
                        LabeledContent("Passkeys", value: passkeyCount == 0 ? "Off" : "On")
                    }
                #else
                    Button {
                        presentedSecurityItem = .blockedUsers
                    } label: {
                        Label("Blocked Users", systemImage: "hand.raised.slash")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)

                    if connectedWebsiteCount > 0 {
                        Button {
                            presentedSecurityItem = .webSessions
                        } label: {
                            LabeledContent("Web Sessions", value: String(connectedWebsiteCount))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.primary)
                    }

                    Button {
                        presentedSecurityItem = .appLock
                    } label: {
                        Label("App Lock", systemImage: "lock")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)

                    Button {
                        presentedSecurityItem = .twoStepVerification
                    } label: {
                        Label("Two-Step Verification", systemImage: "lock.shield")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)

                    Button {
                        presentedSecurityItem = .passkeys
                    } label: {
                        LabeledContent("Passkeys", value: passkeyCount == 0 ? "Off" : "On")
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                #endif
            }

            Section("Privacy") {
                ForEach(telegramPrivacyItems.filter { $0.setting != .userPrivacySettingAllowChatInvites }) { item in
                    Button {
                        selectedItem = item
                    } label: {
                        LabeledContent(
                            item.title,
                            value: TelegramPrivacyOption(rules: rules[item.setting] ?? emptyPrivacyRules).title,
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                TelegramIncomingMessagePrivacyRow(service: service)

                if let groupsItem = telegramPrivacyItems.first(where: {
                    $0.setting == .userPrivacySettingAllowChatInvites
                }) {
                    Button {
                        selectedItem = groupsItem
                    } label: {
                        LabeledContent(
                            groupsItem.title,
                            value: TelegramPrivacyOption(
                                rules: rules[groupsItem.setting] ?? emptyPrivacyRules,
                            ).title,
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Section {
                Picker("Auto-Delete Messages", selection: autoDeleteBinding) {
                    ForEach(TelegramAutoDeleteDuration.allCases) { duration in
                        Text(duration.title).tag(duration)
                    }
                }
                .disabled(isSavingAutoDelete)
            } footer: {
                Text("Automatically delete messages in newly started chats after the selected period.")
            }

            if canAutoArchiveUnknownChats {
                Section {
                    Toggle("Archive and Mute New Chats", isOn: autoArchiveBinding)
                        .disabled(isSavingAutoArchive)
                } footer: {
                    Text("Automatically archive and mute new chats from people who aren't in your contacts.")
                }
            }

            Section("Delete My Account") {
                Picker("If Away For", selection: accountDeletionBinding) {
                    ForEach(TelegramAccountDeletionPeriod.allCases) { period in
                        Text(period.title).tag(period)
                    }
                }
                .disabled(isSavingAccountDeletion)

                Button("Delete My Account Now", role: .destructive) {
                    showsDeleteAccountConfirmation = true
                }
                .disabled(isDeletingAccount)
            }

            Section {
                #if os(iOS)
                    NavigationLink {
                        TelegramDataPrivacySettingsView(service: service)
                    } label: {
                        Text("Data Settings")
                    }
                #else
                    Button {
                        presentedSecurityItem = .dataSettings
                    } label: {
                        Text("Data Settings")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                #endif
            }
        }
        .navigationTitle("Privacy and Security")
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await loadOptions()
            await loadAutoDelete()
            await loadConnectedWebsites()
            await loadAutoArchiveSettings()
            await loadAccountDeletionPeriod()
            await loadPasskeys()
        }
        .sheet(item: $selectedItem) { item in
            TelegramPrivacyDetailView(
                service: service,
                item: item,
                rules: rules[item.setting] ?? emptyPrivacyRules,
            ) { newRules in
                rules[item.setting] = newRules
            }
        }
        #if os(macOS)
        .sheet(item: $presentedSecurityItem) { item in
            NavigationStack {
                securityDestination(item)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { presentedSecurityItem = nil }
                        }
                    }
            }
            .frame(minWidth: 440, minHeight: 420)
        }
        #endif
        .alert("Couldn't Load Privacy Settings", isPresented: errorIsPresented) {
                Button("OK") {}
            } message: {
                Text(errorMessage ?? "")
            }
            .alert("Delete Account?", isPresented: $showsDeleteAccountConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete Account", role: .destructive) { deleteAccount() }
            } message: {
                Text(
                    "This permanently deletes your Telegram account, all your messages, and removes "
                        + "you from every group and channel. It cannot be undone.",
                )
            }
            .alert(
                "Couldn't Delete Account",
                isPresented: Binding(
                    get: { deleteAccountFailure != nil },
                    set: {
                        if !$0 {
                            deleteAccountFailure = nil
                        }
                    },
                ),
            ) {
                Button("Open Deactivation Page") {
                    if let url = URL(string: "https://my.telegram.org/auth?to=deactivate") {
                        openURL(url)
                    }
                }
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteAccountFailure ?? "")
            }
    }

    // MARK: Private

    #if os(macOS)
    private enum SecurityItem: String, Identifiable {
        case appLock
        case blockedUsers
        case dataSettings
        case passkeys
        case twoStepVerification
        case webSessions

        // MARK: Internal

        var id: Self { self }
    }

    @ViewBuilder private func securityDestination(_ item: SecurityItem) -> some View {
        switch item {
        case .appLock:
            TelegramAppLockSettingsView()
        case .blockedUsers:
            BlockedUsersView(service: service)
        case .dataSettings:
            TelegramDataPrivacySettingsView(service: service)
        case .passkeys:
            TelegramPasskeysView(service: service) { passkeyCount = $0 }
        case .twoStepVerification:
            TelegramTwoStepVerificationView(service: service)
        case .webSessions:
            TelegramWebSessionsView(service: service) { connectedWebsiteCount = $0 }
        }
    }
    #endif

    @State private var autoDelete = TelegramAutoDeleteDuration.off
    @State private var accountDeletionPeriod = TelegramAccountDeletionPeriod.sixMonths
    @State private var archiveSettings: ArchiveChatListSettings?
    @State private var canAutoArchiveUnknownChats = false
    @State private var connectedWebsiteCount = 0
    @State private var errorMessage: String?
    @State private var hasLoaded = false
    @State private var isSavingAutoDelete = false
    @State private var isSavingAccountDeletion = false
    @State private var isSavingAutoArchive = false
    @State private var isDeletingAccount = false
    @State private var showsDeleteAccountConfirmation = false
    @State private var deleteAccountFailure: String?
    @State private var passkeyCount = 0
    @State private var rules = [UserPrivacySetting: UserPrivacySettingRules]()
    @State private var selectedItem: TelegramPrivacyItem?
    #if os(macOS)
    @State private var presentedSecurityItem: SecurityItem?
    #endif

    @Environment(\.openURL) private var openURL

    private let service: any TelegramService

    private var emptyPrivacyRules: UserPrivacySettingRules {
        UserPrivacySettingRules(rules: [.userPrivacySettingRuleAllowAll])
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    errorMessage = nil
                }
            },
        )
    }

    private var autoDeleteBinding: Binding<TelegramAutoDeleteDuration> {
        Binding(
            get: { autoDelete },
            set: { newValue in
                let previousValue = autoDelete
                autoDelete = newValue
                isSavingAutoDelete = true
                Task {
                    defer { isSavingAutoDelete = false }
                    do {
                        _ = try await service.setDefaultMessageAutoDeleteTime(
                            messageAutoDeleteTime: MessageAutoDeleteTime(time: newValue.rawValue),
                        )
                    } catch {
                        autoDelete = previousValue
                        errorMessage = telegramErrorDescription(error)
                    }
                }
            },
        )
    }

    private var accountDeletionBinding: Binding<TelegramAccountDeletionPeriod> {
        Binding(
            get: { accountDeletionPeriod },
            set: { newValue in
                let previousValue = accountDeletionPeriod
                accountDeletionPeriod = newValue
                isSavingAccountDeletion = true
                Task {
                    defer { isSavingAccountDeletion = false }
                    do {
                        _ = try await service.setAccountTtl(ttl: AccountTtl(days: newValue.rawValue))
                    } catch {
                        accountDeletionPeriod = previousValue
                        errorMessage = telegramErrorDescription(error)
                    }
                }
            },
        )
    }

    private var autoArchiveBinding: Binding<Bool> {
        Binding(
            get: { archiveSettings?.archiveAndMuteNewChatsFromUnknownUsers ?? false },
            set: { newValue in
                guard let previousSettings = archiveSettings else { return }
                let newSettings = ArchiveChatListSettings(
                    archiveAndMuteNewChatsFromUnknownUsers: newValue,
                    keepChatsFromFoldersArchived: previousSettings.keepChatsFromFoldersArchived,
                    keepUnmutedChatsArchived: previousSettings.keepUnmutedChatsArchived,
                )
                archiveSettings = newSettings
                isSavingAutoArchive = true
                Task {
                    defer { isSavingAutoArchive = false }
                    do {
                        _ = try await service.setArchiveChatListSettings(settings: newSettings)
                    } catch {
                        archiveSettings = previousSettings
                        errorMessage = telegramErrorDescription(error)
                    }
                }
            },
        )
    }

    @MainActor private func deleteAccount() {
        guard !isDeletingAccount else { return }
        isDeletingAccount = true
        Task {
            defer { isDeletingAccount = false }
            do {
                // On success TDLib logs out and the app returns to the login screen on its own.
                _ = try await service.deleteAccount(reason: nil, password: nil)
            } catch {
                // `deleteAccount` needs the two-step-verification password when one is set, which
                // this screen can't collect - point the user at the web deactivation flow instead.
                deleteAccountFailure = telegramErrorDescription(error)
                    + "\n\nIf you use two-step verification, finish deleting your account on "
                    + "Telegram's website."
            }
        }
    }

    @MainActor private func loadAutoDelete() async {
        guard let time = try? await service.getDefaultMessageAutoDeleteTime() else { return }
        autoDelete = TelegramAutoDeleteDuration(seconds: time.time)
    }

    @MainActor private func loadAccountDeletionPeriod() async {
        guard let ttl = try? await service.getAccountTtl() else { return }
        accountDeletionPeriod = TelegramAccountDeletionPeriod(days: ttl.days)
    }

    @MainActor private func loadAutoArchiveSettings() async {
        guard case .optionValueBoolean(let capability) = try? await service.getOption(
            name: "can_archive_and_mute_new_chats_from_unknown_users",
        ) else { return }
        canAutoArchiveUnknownChats = capability.value
        guard capability.value else { return }
        archiveSettings = try? await service.getArchiveChatListSettings()
    }

    @MainActor private func loadConnectedWebsites() async {
        connectedWebsiteCount = await (try? service.getConnectedWebsites().websites.count) ?? 0
    }

    @MainActor private func loadOptions() async {
        var resolvedRules = [UserPrivacySetting: UserPrivacySettingRules]()
        var loadError: Swift.Error?
        await withTaskGroup(of: (UserPrivacySetting, Result<UserPrivacySettingRules, Swift.Error>).self) { group in
            for item in telegramPrivacyItems {
                group.addTask {
                    do {
                        return try await (
                            item.setting,
                            .success(service.getUserPrivacySettingRules(setting: item.setting)),
                        )
                    } catch {
                        return (item.setting, .failure(error))
                    }
                }
            }
            for await (setting, result) in group {
                switch result {
                case .success(let rules):
                    resolvedRules[setting] = rules
                case .failure(let error):
                    loadError = error
                }
            }
        }
        rules = resolvedRules
        if let loadError {
            errorMessage = telegramErrorDescription(loadError)
        }
    }

    @MainActor private func loadPasskeys() async {
        passkeyCount = await (try? service.getLoginPasskeys().passkeys.count) ?? 0
    }
}

// MARK: - TelegramPrivacyDetailView

struct TelegramPrivacyDetailView: View {
    // MARK: Lifecycle

    init(
        service: any TelegramService,
        item: TelegramPrivacyItem,
        rules: UserPrivacySettingRules,
        onSaved: @escaping (UserPrivacySettingRules) -> Void,
    ) {
        self.service = service
        self.item = item
        _rules = State(initialValue: rules)
        self.onSaved = onSaved
    }

    // MARK: Internal

    let service: any TelegramService
    let item: TelegramPrivacyItem
    let onSaved: (UserPrivacySettingRules) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(item.availableOptions) { candidate in
                        Button {
                            select(candidate)
                        } label: {
                            HStack {
                                Text(candidate.title)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if candidate == option {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(candidate == option ? [.isSelected] : [])
                        .disabled(isSaving)
                    }
                } footer: {
                    if let footer = item.footer {
                        Text(footer)
                    }
                }

                Section {
                    if option != .everybody {
                        exceptionButton(
                            .alwaysAllow,
                            count: alwaysAllowUserIds.count + alwaysAllowChatIds.count,
                        )
                    }
                    if option != .nobody {
                        exceptionButton(
                            .neverAllow,
                            count: neverAllowUserIds.count + neverAllowChatIds.count,
                        )
                    }
                } header: {
                    Text("Exceptions")
                } footer: {
                    Text("Exceptions take priority over the general setting above.")
                }

                TelegramRelatedPrivacySettingsSection(service: service, setting: item.setting)
            }
            .navigationTitle(item.title)
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 360)
        #endif
        .sheet(item: $exceptionBeingEdited) { exception in
            TelegramPrivacyExceptionPicker(
                service: service,
                title: exception.title,
                selection: TelegramPrivacyExceptionSelection(
                    userIds: exception == .alwaysAllow ? alwaysAllowUserIds : neverAllowUserIds,
                    chatIds: exception == .alwaysAllow ? alwaysAllowChatIds : neverAllowChatIds,
                ),
            ) { selection in
                update(exception, selection: selection)
            }
        }
        .alert("Couldn't Update Privacy Setting", isPresented: errorIsPresented) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Private

    private enum PrivacyException: String, Identifiable {
        case alwaysAllow
        case neverAllow

        // MARK: Internal

        var id: Self { self }

        var title: String {
            switch self {
            case .alwaysAllow: "Always Allow"
            case .neverAllow: "Never Allow"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?
    @State private var exceptionBeingEdited: PrivacyException?
    @State private var isSaving = false
    @State private var rules: UserPrivacySettingRules

    private var option: TelegramPrivacyOption {
        TelegramPrivacyOption(rules: rules)
    }

    private var alwaysAllowUserIds: Set<Int64> {
        TelegramPrivacyRules.alwaysAllowUserIds(in: rules)
    }

    private var neverAllowUserIds: Set<Int64> {
        TelegramPrivacyRules.neverAllowUserIds(in: rules)
    }

    private var alwaysAllowChatIds: Set<Int64> {
        TelegramPrivacyRules.alwaysAllowChatIds(in: rules)
    }

    private var neverAllowChatIds: Set<Int64> {
        TelegramPrivacyRules.neverAllowChatIds(in: rules)
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    errorMessage = nil
                }
            },
        )
    }

    private func exceptionButton(_ exception: PrivacyException, count: Int) -> some View {
        Button {
            exceptionBeingEdited = exception
        } label: {
            LabeledContent(exception.title, value: count == 0 ? "Add" : String(count))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
    }

    @MainActor private func select(_ candidate: TelegramPrivacyOption) {
        guard candidate != option, !isSaving else { return }
        save(TelegramPrivacyRules.replacingBaseOption(in: rules, with: candidate))
    }

    @MainActor private func update(
        _ exception: PrivacyException,
        selection: TelegramPrivacyExceptionSelection,
    ) {
        let updatedRules = TelegramPrivacyRules.replacingUserExceptions(
            in: rules,
            alwaysAllow: exception == .alwaysAllow ? selection.userIds : alwaysAllowUserIds,
            neverAllow: exception == .neverAllow ? selection.userIds : neverAllowUserIds,
            alwaysAllowChatIds: exception == .alwaysAllow ? selection.chatIds : alwaysAllowChatIds,
            neverAllowChatIds: exception == .neverAllow ? selection.chatIds : neverAllowChatIds,
        )
        save(updatedRules)
    }

    @MainActor private func save(_ updatedRules: UserPrivacySettingRules) {
        guard updatedRules != rules, !isSaving else { return }
        let previousRules = rules
        rules = updatedRules
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                _ = try await service.setUserPrivacySettingRules(rules: updatedRules, setting: item.setting)
                onSaved(updatedRules)
            } catch {
                rules = previousRules
                errorMessage = telegramErrorDescription(error)
            }
        }
    }
}
