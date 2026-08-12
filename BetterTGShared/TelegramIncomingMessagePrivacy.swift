// TelegramIncomingMessagePrivacy.swift

import SwiftUI
@preconcurrency import TDLibKit

// MARK: - TelegramIncomingMessagePrivacyMode

enum TelegramIncomingMessagePrivacyMode: CaseIterable, Equatable, Identifiable {
    case everybody
    case contactsAndPremium
    case paidMessages

    // MARK: Lifecycle

    init(settings: NewChatPrivacySettings) {
        self =
            if settings.incomingPaidMessageStarCount > 0 {
                .paidMessages
            } else if settings.allowNewChatsFromUnknownUsers {
                .everybody
            } else {
                .contactsAndPremium
            }
    }

    // MARK: Internal

    var id: Self { self }

    var title: String {
        switch self {
        case .everybody: "Everybody"
        case .contactsAndPremium: "Contacts and Premium Users"
        case .paidMessages: "Paid Messages"
        }
    }

    func settings(paidStars: Int64) -> NewChatPrivacySettings {
        switch self {
        case .everybody:
            NewChatPrivacySettings(allowNewChatsFromUnknownUsers: true, incomingPaidMessageStarCount: 0)
        case .contactsAndPremium:
            NewChatPrivacySettings(allowNewChatsFromUnknownUsers: false, incomingPaidMessageStarCount: 0)
        case .paidMessages:
            NewChatPrivacySettings(
                allowNewChatsFromUnknownUsers: true,
                incomingPaidMessageStarCount: max(1, paidStars),
            )
        }
    }
}

// MARK: - TelegramIncomingMessagePrivacyRow

struct TelegramIncomingMessagePrivacyRow: View {
    // MARK: Internal

    let service: any TelegramService

    var body: some View {
        Group {
            if canSetPrivacy, let settings {
                Button {
                    presentedConfiguration = TelegramIncomingMessagePrivacyConfiguration(settings: settings)
                } label: {
                    LabeledContent("Messages", value: TelegramIncomingMessagePrivacyMode(settings: settings).title)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await loadSettings()
        }
        .sheet(item: $presentedConfiguration) { configuration in
            TelegramIncomingMessagePrivacyView(service: service, settings: configuration.settings) { settings in
                self.settings = settings
            }
        }
    }

    // MARK: Private

    @State private var canSetPrivacy = false
    @State private var hasLoaded = false
    @State private var presentedConfiguration: TelegramIncomingMessagePrivacyConfiguration?
    @State private var settings: NewChatPrivacySettings?

    @MainActor private func loadSettings() async {
        guard case .optionValueBoolean(let capability) = try? await service.getOption(
            name: "can_set_new_chat_privacy_settings",
        ), capability.value else { return }
        guard let loadedSettings = try? await service.getNewChatPrivacySettings() else { return }
        settings = loadedSettings
        canSetPrivacy = true
    }
}

// MARK: - TelegramIncomingMessagePrivacyConfiguration

private struct TelegramIncomingMessagePrivacyConfiguration: Identifiable {
    let id = UUID()
    let settings: NewChatPrivacySettings
}

// MARK: - TelegramIncomingMessagePrivacyView

private struct TelegramIncomingMessagePrivacyView: View {
    // MARK: Lifecycle

    init(
        service: any TelegramService,
        settings: NewChatPrivacySettings,
        onSaved: @escaping (NewChatPrivacySettings) -> Void,
    ) {
        self.service = service
        _settings = State(initialValue: settings)
        _paidStars = State(initialValue: max(1, settings.incomingPaidMessageStarCount))
        self.onSaved = onSaved
    }

    // MARK: Internal

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(availableModes) { candidate in
                        Button {
                            select(candidate)
                        } label: {
                            HStack {
                                Text(candidate.title)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if candidate == mode {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                        .accessibilityHidden(true)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(candidate == mode ? [.isSelected] : [])
                        .disabled(isSaving)
                    }
                } footer: {
                    Text("Premium users can contact you regardless of the Contacts and Premium Users setting.")
                }

                if mode == .paidMessages {
                    Section {
                        TextField("Telegram Stars", value: $paidStars, format: .number)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif

                        Button("Update Price") {
                            updatePaidPrice()
                        }
                        .disabled(isSaving || normalizedPaidStars == settings.incomingPaidMessageStarCount)
                    } header: {
                        Text("Price per Message")
                    } footer: {
                        Text("Non-contacts must pay this many Telegram Stars for each message.")
                    }

                    if unpaidRules != nil {
                        Section("Exceptions") {
                            Button {
                                presentedSheet = .unpaidExceptions
                            } label: {
                                LabeledContent(
                                    "Allow Without Payment",
                                    value: exceptionCount == 0 ? "Add" : String(exceptionCount),
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(isSavingRules)
                        }
                    }
                }
            }
            .navigationTitle("Messages")
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
        .frame(minWidth: 420, minHeight: 440)
        #endif
        .task {
            guard !hasLoadedCapabilities else { return }
            hasLoadedCapabilities = true
            await loadCapabilitiesAndRules()
        }
        .sheet(item: $presentedSheet) { _ in
            TelegramPrivacyExceptionPicker(
                service: service,
                title: "Allow Without Payment",
                selection: exceptionSelection,
            ) { selection in
                updateUnpaidExceptions(selection)
            }
        }
        .alert("Couldn't Update Message Privacy", isPresented: errorIsPresented) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Private

    private enum PresentedSheet: String, Identifiable {
        case unpaidExceptions

        // MARK: Internal

        var id: Self { self }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var canEnablePaidMessages = false
    @State private var errorMessage: String?
    @State private var hasLoadedCapabilities = false
    @State private var isSaving = false
    @State private var isSavingRules = false
    @State private var paidMessageStarCountMax: Int64 = 10000
    @State private var paidStars: Int64
    @State private var presentedSheet: PresentedSheet?
    @State private var settings: NewChatPrivacySettings
    @State private var unpaidRules: UserPrivacySettingRules?

    private let onSaved: (NewChatPrivacySettings) -> Void
    private let service: any TelegramService

    private var availableModes: [TelegramIncomingMessagePrivacyMode] {
        TelegramIncomingMessagePrivacyMode.allCases.filter { mode in
            mode != .paidMessages || canEnablePaidMessages || self.mode == .paidMessages
        }
    }

    private var mode: TelegramIncomingMessagePrivacyMode {
        TelegramIncomingMessagePrivacyMode(settings: settings)
    }

    private var normalizedPaidStars: Int64 {
        min(max(1, paidStars), paidMessageStarCountMax)
    }

    private var exceptionSelection: TelegramPrivacyExceptionSelection {
        guard let unpaidRules else {
            return TelegramPrivacyExceptionSelection(userIds: [], chatIds: [])
        }
        return TelegramPrivacyExceptionSelection(
            userIds: TelegramPrivacyRules.alwaysAllowUserIds(in: unpaidRules),
            chatIds: TelegramPrivacyRules.alwaysAllowChatIds(in: unpaidRules),
        )
    }

    private var exceptionCount: Int {
        exceptionSelection.userIds.count + exceptionSelection.chatIds.count
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

    @MainActor private func loadCapabilitiesAndRules() async {
        if case .optionValueBoolean(let capability) = try? await service.getOption(name: "can_enable_paid_messages") {
            canEnablePaidMessages = capability.value
        }
        if case .optionValueInteger(let maximum) = try? await service.getOption(name: "paid_message_star_count_max") {
            paidMessageStarCountMax = max(1, maximum.value.rawValue)
        }
        unpaidRules = try? await service.getUserPrivacySettingRules(
            setting: .userPrivacySettingAllowUnpaidMessages,
        )
    }

    @MainActor private func select(_ candidate: TelegramIncomingMessagePrivacyMode) {
        guard candidate != mode, !isSaving else { return }
        save(candidate.settings(paidStars: normalizedPaidStars))
    }

    @MainActor private func updatePaidPrice() {
        paidStars = normalizedPaidStars
        save(.init(
            allowNewChatsFromUnknownUsers: true,
            incomingPaidMessageStarCount: normalizedPaidStars,
        ))
    }

    @MainActor private func save(_ updatedSettings: NewChatPrivacySettings) {
        guard updatedSettings != settings, !isSaving else { return }
        let previousSettings = settings
        settings = updatedSettings
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                _ = try await service.setNewChatPrivacySettings(settings: updatedSettings)
                onSaved(updatedSettings)
            } catch {
                settings = previousSettings
                paidStars = max(1, previousSettings.incomingPaidMessageStarCount)
                errorMessage = telegramErrorDescription(error)
            }
        }
    }

    @MainActor private func updateUnpaidExceptions(_ selection: TelegramPrivacyExceptionSelection) {
        guard let unpaidRules, !isSavingRules else { return }
        let updatedRules = TelegramPrivacyRules.replacingUserExceptions(
            in: unpaidRules,
            alwaysAllow: selection.userIds,
            neverAllow: TelegramPrivacyRules.neverAllowUserIds(in: unpaidRules),
            alwaysAllowChatIds: selection.chatIds,
            neverAllowChatIds: TelegramPrivacyRules.neverAllowChatIds(in: unpaidRules),
        )
        guard updatedRules != unpaidRules else { return }
        isSavingRules = true
        Task {
            defer { isSavingRules = false }
            do {
                _ = try await service.setUserPrivacySettingRules(
                    rules: updatedRules,
                    setting: .userPrivacySettingAllowUnpaidMessages,
                )
                self.unpaidRules = updatedRules
            } catch {
                errorMessage = telegramErrorDescription(error)
            }
        }
    }
}
