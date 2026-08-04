// TelegramPrivacySettings.swift

import SwiftUI
import TDLibKit

// MARK: - TelegramPrivacyOption

enum TelegramPrivacyOption: CaseIterable, Identifiable {
    case everybody
    case myContacts
    case nobody

    // MARK: Lifecycle

    /// Only looks at the first rule - per-user "Always Allow"/"Never Allow" exceptions (any
    /// further rules in the list) aren't represented here; an exception-bearing or otherwise
    /// unrecognized first rule falls back to `.everybody` as a safe display default.
    init(rules: UserPrivacySettingRules) {
        self =
            switch rules.rules.first {
            case .userPrivacySettingRuleAllowContacts:
                .myContacts
            case .userPrivacySettingRuleRestrictAll:
                .nobody
            default:
                .everybody
            }
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

    /// Always a single-rule list - selecting an option here overwrites any existing per-user
    /// exceptions on this setting.
    var rules: UserPrivacySettingRules {
        switch self {
        case .everybody: UserPrivacySettingRules(rules: [.userPrivacySettingRuleAllowAll])
        case .myContacts: UserPrivacySettingRules(rules: [.userPrivacySettingRuleAllowContacts])
        case .nobody: UserPrivacySettingRules(rules: [.userPrivacySettingRuleRestrictAll])
        }
    }
}

// MARK: - TelegramPrivacyItem

struct TelegramPrivacyItem: Identifiable {
    let setting: UserPrivacySetting
    let title: String
    let footer: String?

    var id: String { title }
}

let telegramPrivacyItems: [TelegramPrivacyItem] = [
    TelegramPrivacyItem(setting: .userPrivacySettingShowStatus, title: "Last Seen & Online", footer: nil),
    TelegramPrivacyItem(setting: .userPrivacySettingShowProfilePhoto, title: "Profile Photo", footer: nil),
    TelegramPrivacyItem(setting: .userPrivacySettingShowPhoneNumber, title: "Phone Number", footer: nil),
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
    TelegramPrivacyItem(setting: .userPrivacySettingShowBio, title: "Bio", footer: nil),
]

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
        List(telegramPrivacyItems) { item in
            Button {
                selectedItem = item
            } label: {
                LabeledContent(item.title, value: (options[item.setting] ?? .everybody).title)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .navigationTitle("Privacy")
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await loadOptions()
        }
        .sheet(item: $selectedItem) { item in
            TelegramPrivacyDetailView(
                service: service,
                item: item,
                option: options[item.setting] ?? .everybody,
            ) { newOption in
                options[item.setting] = newOption
            }
        }
        .alert("Couldn't Load Privacy Settings", isPresented: errorIsPresented) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Private

    @State private var errorMessage: String?
    @State private var hasLoaded = false
    @State private var options = [UserPrivacySetting: TelegramPrivacyOption]()
    @State private var selectedItem: TelegramPrivacyItem?

    private let service: any TelegramService

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

    @MainActor private func loadOptions() async {
        var resolvedOptions = [UserPrivacySetting: TelegramPrivacyOption]()
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
                    resolvedOptions[setting] = TelegramPrivacyOption(rules: rules)
                case .failure(let error):
                    loadError = error
                }
            }
        }
        options = resolvedOptions
        if let loadError {
            errorMessage = telegramErrorDescription(loadError)
        }
    }
}

// MARK: - TelegramPrivacyDetailView

private struct TelegramPrivacyDetailView: View {
    // MARK: Internal

    let service: any TelegramService
    let item: TelegramPrivacyItem
    @State var option: TelegramPrivacyOption

    let onSaved: (TelegramPrivacyOption) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(TelegramPrivacyOption.allCases) { candidate in
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
        .frame(minWidth: 360, minHeight: 260)
        #endif
        .alert("Couldn't Update Privacy Setting", isPresented: errorIsPresented) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?
    @State private var isSaving = false

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

    @MainActor private func select(_ candidate: TelegramPrivacyOption) {
        guard candidate != option, !isSaving else { return }
        let previousOption = option
        option = candidate
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                _ = try await service.setUserPrivacySettingRules(rules: candidate.rules, setting: item.setting)
                onSaved(candidate)
                dismiss()
            } catch {
                option = previousOption
                errorMessage = telegramErrorDescription(error)
            }
        }
    }
}
