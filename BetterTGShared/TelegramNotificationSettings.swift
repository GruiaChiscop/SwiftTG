// TelegramNotificationSettings.swift

import SwiftUI
@preconcurrency import TDLibKit

/// TDLib's convention for "muted forever" - `muteFor` is a duration in seconds, and the official
/// clients use Int32.max as a practically-infinite mute rather than modeling an explicit boolean.
private let mutedForeverDuration = Int(Int32.max)

extension ScopeNotificationSettings {
    static let defaultSettings = ScopeNotificationSettings(
        disableMentionNotifications: false,
        disablePinnedMessageNotifications: false,
        muteFor: 0,
        muteStories: false,
        showPreview: true,
        showStoryPoster: true,
        soundId: -1,
        storySoundId: -1,
        useDefaultMuteStories: true,
    )

    var isEnabled: Bool { muteFor <= 0 }

    func withEnabled(_ isEnabled: Bool) -> ScopeNotificationSettings {
        ScopeNotificationSettings(
            disableMentionNotifications: disableMentionNotifications,
            disablePinnedMessageNotifications: disablePinnedMessageNotifications,
            muteFor: isEnabled ? 0 : mutedForeverDuration,
            muteStories: muteStories,
            showPreview: showPreview,
            showStoryPoster: showStoryPoster,
            soundId: soundId,
            storySoundId: storySoundId,
            useDefaultMuteStories: useDefaultMuteStories,
        )
    }

    func withShowPreview(_ showPreview: Bool) -> ScopeNotificationSettings {
        ScopeNotificationSettings(
            disableMentionNotifications: disableMentionNotifications,
            disablePinnedMessageNotifications: disablePinnedMessageNotifications,
            muteFor: muteFor,
            muteStories: muteStories,
            showPreview: showPreview,
            showStoryPoster: showStoryPoster,
            soundId: soundId,
            storySoundId: storySoundId,
            useDefaultMuteStories: useDefaultMuteStories,
        )
    }

    func withSoundId(_ soundId: TdInt64) -> ScopeNotificationSettings {
        ScopeNotificationSettings(
            disableMentionNotifications: disableMentionNotifications,
            disablePinnedMessageNotifications: disablePinnedMessageNotifications,
            muteFor: muteFor,
            muteStories: muteStories,
            showPreview: showPreview,
            showStoryPoster: showStoryPoster,
            soundId: soundId,
            storySoundId: storySoundId,
            useDefaultMuteStories: useDefaultMuteStories,
        )
    }
}

extension ReactionNotificationSettings {
    /// `storyReactionSource` is left at `.reactionNotificationSourceNone` since SwiftTG doesn't
    /// implement Stories - there's no UI to ever turn it on, so it should never silently read as
    /// enabled. Mirrors Telegram-iOS's own `ReactionNotificationSettingsController`, which likewise
    /// only ever exposes `messageReactionSource` as a toggle (no separate poll-vote row) -
    /// `pollVoteSource` is kept in sync with it here instead of exposing a third control.
    static let defaultSettings = ReactionNotificationSettings(
        messageReactionSource: .reactionNotificationSourceAll,
        pollVoteSource: .reactionNotificationSourceAll,
        showPreview: true,
        soundId: -1,
        storyReactionSource: .reactionNotificationSourceNone,
    )

    var isEnabled: Bool {
        if case .reactionNotificationSourceNone = messageReactionSource { return false }
        return true
    }

    func withEnabled(_ isEnabled: Bool) -> ReactionNotificationSettings {
        let source: ReactionNotificationSource = isEnabled
            ? .reactionNotificationSourceAll
            : .reactionNotificationSourceNone
        return ReactionNotificationSettings(
            messageReactionSource: source,
            pollVoteSource: source,
            showPreview: showPreview,
            soundId: soundId,
            storyReactionSource: storyReactionSource,
        )
    }

    func withShowPreview(_ showPreview: Bool) -> ReactionNotificationSettings {
        ReactionNotificationSettings(
            messageReactionSource: messageReactionSource,
            pollVoteSource: pollVoteSource,
            showPreview: showPreview,
            soundId: soundId,
            storyReactionSource: storyReactionSource,
        )
    }

    func withSoundId(_ soundId: TdInt64) -> ReactionNotificationSettings {
        ReactionNotificationSettings(
            messageReactionSource: messageReactionSource,
            pollVoteSource: pollVoteSource,
            showPreview: showPreview,
            soundId: soundId,
            storyReactionSource: storyReactionSource,
        )
    }
}

// MARK: - TelegramNotificationScopeItem

struct TelegramNotificationScopeItem: Identifiable {
    let scope: NotificationSettingsScope
    let title: String

    var id: String { title }
}

let telegramNotificationScopeItems: [TelegramNotificationScopeItem] = [
    TelegramNotificationScopeItem(scope: .notificationSettingsScopePrivateChats, title: "Private Chats"),
    TelegramNotificationScopeItem(scope: .notificationSettingsScopeGroupChats, title: "Groups"),
    TelegramNotificationScopeItem(scope: .notificationSettingsScopeChannelChats, title: "Channels"),
]

// MARK: - TelegramNotificationsView

struct TelegramNotificationsView: View {
    // MARK: Lifecycle

    init(service: any TelegramService) {
        self.service = service
    }

    // MARK: Internal

    var body: some View {
        List {
            Section {
                ForEach(telegramNotificationScopeItems) { item in
                    #if os(iOS)
                        NavigationLink {
                            TelegramNotificationScopeDetailContent(
                                service: service,
                                item: item,
                                settings: settings[item.scope] ?? .defaultSettings,
                            ) { newSettings in
                                settings[item.scope] = newSettings
                            }
                            .navigationTitle(item.title)
                            .navigationBarTitleDisplayMode(.inline)
                        } label: {
                            LabeledContent(item.title, value: statusText(for: item.scope))
                        }
                    #else
                        Button {
                            selectedItem = item
                        } label: {
                            LabeledContent(item.title, value: statusText(for: item.scope))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    #endif
                }

                #if os(iOS)
                    NavigationLink {
                        TelegramReactionNotificationDetailContent(
                            service: service,
                            settings: reactionSettings ?? .defaultSettings,
                        ) { newSettings in
                            reactionSettings = newSettings
                        }
                        .navigationTitle("Reactions")
                        .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        LabeledContent("Reactions", value: reactionStatusText)
                    }
                #else
                    Button {
                        showsReactionDetail = true
                    } label: {
                        LabeledContent("Reactions", value: reactionStatusText)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                #endif
            }

            Section {
                Toggle("Notify When Contacts Join Telegram", isOn: contactJoinedBinding)
                    .disabled(!hasLoadedContactJoinedSetting || isSavingContactJoinedSetting)
            }

            #if os(iOS)
            Section {
                Toggle("Sounds", isOn: inAppSoundBinding)
                Toggle("Vibrate", isOn: inAppVibrateBinding)
                Toggle("Show Previews", isOn: inAppPreviewBinding)
            } header: {
                Text("In-App Notifications")
            } footer: {
                Text("Controls the banner shown for new messages while SwiftTG is open, not push notifications.")
            }
            #endif

            Section {
                Button("Reset All Notifications", role: .destructive) {
                    confirmsReset = true
                }
                .disabled(isResetting)
            }
        }
        .navigationTitle("Notifications")
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await loadSettings()
            await loadContactJoinedSetting()
        }
        // No `getReactionNotificationSettings` exists - TDLib only ever pushes the current value via
        // `updateReactionNotificationSettings`, replayed to late subscribers by
        // `reactionNotificationSettingsPublisher` (a `CurrentValueSubject`, like `chatFoldersPublisher`).
        .onReceive(service.reactionNotificationSettingsPublisher) { reactionSettings = $0 }
        #if os(macOS)
        .sheet(item: $selectedItem) { item in
            TelegramNotificationScopeDetailView(
                service: service,
                item: item,
                settings: settings[item.scope] ?? .defaultSettings,
            ) { newSettings in
                settings[item.scope] = newSettings
            }
        }
        .sheet(isPresented: $showsReactionDetail) {
            NavigationStack {
                TelegramReactionNotificationDetailContent(
                    service: service,
                    settings: reactionSettings ?? .defaultSettings,
                ) { newSettings in
                    reactionSettings = newSettings
                }
                .navigationTitle("Reactions")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { showsReactionDetail = false }
                    }
                }
            }
            .frame(minWidth: 360, minHeight: 320)
        }
        #endif
        .alert(
            "Reset all notification settings?",
            isPresented: $confirmsReset,
        ) {
            Button("Reset", role: .destructive) { Task { await resetAllNotifications() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This resets custom notification settings for every chat back to their defaults.")
        }
        .alert("Couldn't Load Notification Settings", isPresented: errorIsPresented) {
                Button("OK") {}
            } message: {
                Text(errorMessage ?? "")
            }
    }

    // MARK: Private

    @State private var confirmsReset = false
    @State private var contactJoinedEnabled = true
    @State private var errorMessage: String?
    @State private var hasLoaded = false
    @State private var hasLoadedContactJoinedSetting = false
    @State private var isResetting = false
    @State private var isSavingContactJoinedSetting = false
    @State private var reactionSettings: ReactionNotificationSettings?
    #if os(macOS)
    @State private var selectedItem: TelegramNotificationScopeItem?
    @State private var showsReactionDetail = false
    #endif
    @State private var settings = [NotificationSettingsScope: ScopeNotificationSettings]()
    #if os(iOS)
    @State private var inAppSoundEnabled = TelegramInAppNotificationPreferences.soundEnabled
    @State private var inAppVibrateEnabled = TelegramInAppNotificationPreferences.vibrateEnabled
    @State private var inAppPreviewsEnabled = TelegramInAppNotificationPreferences.previewsEnabled
    #endif

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

    private var reactionStatusText: String {
        (reactionSettings ?? .defaultSettings).isEnabled ? "On" : "Off"
    }

    private var contactJoinedBinding: Binding<Bool> {
        Binding(
            get: { contactJoinedEnabled },
            set: { newValue in
                let previousValue = contactJoinedEnabled
                contactJoinedEnabled = newValue
                isSavingContactJoinedSetting = true
                Task {
                    defer { isSavingContactJoinedSetting = false }
                    do {
                        _ = try await service.setOption(
                            name: "disable_contact_registered_notifications",
                            value: .optionValueBoolean(OptionValueBoolean(value: !newValue)),
                        )
                    } catch {
                        contactJoinedEnabled = previousValue
                        errorMessage = telegramErrorDescription(error)
                    }
                }
            },
        )
    }

    #if os(iOS)
    private var inAppSoundBinding: Binding<Bool> {
        Binding(
            get: { inAppSoundEnabled },
            set: { newValue in
                inAppSoundEnabled = newValue
                TelegramInAppNotificationPreferences.soundEnabled = newValue
            },
        )
    }

    private var inAppVibrateBinding: Binding<Bool> {
        Binding(
            get: { inAppVibrateEnabled },
            set: { newValue in
                inAppVibrateEnabled = newValue
                TelegramInAppNotificationPreferences.vibrateEnabled = newValue
            },
        )
    }

    private var inAppPreviewBinding: Binding<Bool> {
        Binding(
            get: { inAppPreviewsEnabled },
            set: { newValue in
                inAppPreviewsEnabled = newValue
                TelegramInAppNotificationPreferences.previewsEnabled = newValue
            },
        )
    }
    #endif

    private func statusText(for scope: NotificationSettingsScope) -> String {
        (settings[scope] ?? .defaultSettings).isEnabled ? "On" : "Off"
    }

    @MainActor private func loadContactJoinedSetting() async {
        defer { hasLoadedContactJoinedSetting = true }
        guard case .optionValueBoolean(let disabled) = try? await service.getOption(
            name: "disable_contact_registered_notifications",
        ) else { return }
        contactJoinedEnabled = !disabled.value
    }

    @MainActor private func resetAllNotifications() async {
        isResetting = true
        defer { isResetting = false }
        do {
            _ = try await service.resetAllNotificationSettings()
            settings.removeAll()
            reactionSettings = nil
            await loadSettings()
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }

    @MainActor private func loadSettings() async {
        var resolvedSettings = [NotificationSettingsScope: ScopeNotificationSettings]()
        var loadError: Swift.Error?
        await withTaskGroup(of: (NotificationSettingsScope, Result<ScopeNotificationSettings, Swift.Error>)
            .self)
        { group in
            for item in telegramNotificationScopeItems {
                group.addTask {
                    do {
                        return try await (
                            item.scope,
                            .success(service.getScopeNotificationSettings(scope: item.scope)),
                        )
                    } catch {
                        return (item.scope, .failure(error))
                    }
                }
            }
            for await (scope, result) in group {
                switch result {
                case .success(let scopeSettings):
                    resolvedSettings[scope] = scopeSettings
                case .failure(let error):
                    loadError = error
                }
            }
        }
        settings = resolvedSettings
        if let loadError {
            errorMessage = telegramErrorDescription(loadError)
        }
    }
}

// MARK: - TelegramNotificationScopeDetailView

#if os(macOS)
private struct TelegramNotificationScopeDetailView: View {
    // MARK: Internal

    let service: any TelegramService
    let item: TelegramNotificationScopeItem
    let settings: ScopeNotificationSettings

    let onSaved: (ScopeNotificationSettings) -> Void

    var body: some View {
        NavigationStack {
            TelegramNotificationScopeDetailContent(service: service, item: item, settings: settings, onSaved: onSaved)
                .navigationTitle(item.title)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .frame(minWidth: 360, minHeight: 320)
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
}
#endif

// MARK: - TelegramNotificationScopeDetailContent

private struct TelegramNotificationScopeDetailContent: View {
    // MARK: Internal

    let service: any TelegramService
    let item: TelegramNotificationScopeItem
    @State var settings: ScopeNotificationSettings

    let onSaved: (ScopeNotificationSettings) -> Void

    var body: some View {
        Form {
            Section {
                Toggle("Enabled", isOn: enabledBinding)
                Toggle("Show Preview", isOn: showPreviewBinding)
                    .disabled(!settings.isEnabled)
                #if os(iOS)
                    NavigationLink {
                        TelegramNotificationSoundPickerView(
                            service: service,
                            selectedSoundId: settings.soundId,
                        ) { newSoundId in
                            saveSoundId(newSoundId)
                        }
                    } label: {
                        LabeledContent("Sound", value: soundDisplayName)
                    }
                    .disabled(!settings.isEnabled)
                #else
                    Button {
                        showsSoundPicker = true
                    } label: {
                        LabeledContent("Sound", value: soundDisplayName)
                            .foregroundStyle(.primary)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!settings.isEnabled)
                #endif
            }

            Section {
                Toggle("Mentions as Regular Notifications", isOn: disableMentionBinding)
                Toggle("Pinned Messages as Regular Notifications", isOn: disablePinnedBinding)
            } footer: {
                Text(
                    "When on, mentions and pinned messages in this scope no longer stand out from ordinary unread messages.",
                )
            }
        }
        .task(id: settings.soundId) {
            guard settings.soundId > 0 else {
                soundTitle = nil
                return
            }
            soundTitle = try? await service.getSavedNotificationSound(notificationSoundId: settings.soundId).title
        }
        .alert("Couldn't Update Notification Settings", isPresented: errorIsPresented) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
        #if os(macOS)
        .sheet(isPresented: $showsSoundPicker) {
            TelegramNotificationSoundPickerSheet(service: service, selectedSoundId: settings.soundId) { newSoundId in
                saveSoundId(newSoundId)
            }
        }
        #endif
    }

    // MARK: Private

    @State private var errorMessage: String?
    @State private var isSaving = false
    #if os(macOS)
    @State private var showsSoundPicker = false
    #endif
    @State private var soundTitle: String?

    private var soundDisplayName: String {
        if settings.soundId <= -1 {
            return "Default"
        }
        if settings.soundId == 0 {
            return "Off"
        }
        return soundTitle ?? "…"
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

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { settings.isEnabled },
            set: { save(settings.withEnabled($0)) },
        )
    }

    private var showPreviewBinding: Binding<Bool> {
        Binding(
            get: { settings.showPreview },
            set: { save(settings.withShowPreview($0)) },
        )
    }

    private var disableMentionBinding: Binding<Bool> {
        Binding(
            get: { settings.disableMentionNotifications },
            set: { newValue in
                save(ScopeNotificationSettings(
                    disableMentionNotifications: newValue,
                    disablePinnedMessageNotifications: settings.disablePinnedMessageNotifications,
                    muteFor: settings.muteFor,
                    muteStories: settings.muteStories,
                    showPreview: settings.showPreview,
                    showStoryPoster: settings.showStoryPoster,
                    soundId: settings.soundId,
                    storySoundId: settings.storySoundId,
                    useDefaultMuteStories: settings.useDefaultMuteStories,
                ))
            },
        )
    }

    private var disablePinnedBinding: Binding<Bool> {
        Binding(
            get: { settings.disablePinnedMessageNotifications },
            set: { newValue in
                save(ScopeNotificationSettings(
                    disableMentionNotifications: settings.disableMentionNotifications,
                    disablePinnedMessageNotifications: newValue,
                    muteFor: settings.muteFor,
                    muteStories: settings.muteStories,
                    showPreview: settings.showPreview,
                    showStoryPoster: settings.showStoryPoster,
                    soundId: settings.soundId,
                    storySoundId: settings.storySoundId,
                    useDefaultMuteStories: settings.useDefaultMuteStories,
                ))
            },
        )
    }

    private func saveSoundId(_ newSoundId: TdInt64) {
        save(settings.withSoundId(newSoundId))
        Task {
            await TelegramNotificationSoundCache.refresh(
                scope: item.scope,
                soundId: newSoundId,
                service: service,
            )
        }
    }

    @MainActor private func save(_ newSettings: ScopeNotificationSettings) {
        guard !isSaving else { return }
        let previousSettings = settings
        settings = newSettings
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                _ = try await service.setScopeNotificationSettings(notificationSettings: newSettings, scope: item.scope)
                onSaved(newSettings)
            } catch {
                settings = previousSettings
                errorMessage = telegramErrorDescription(error)
            }
        }
    }
}

// MARK: - TelegramReactionNotificationDetailContent

/// Mirrors `TelegramNotificationScopeDetailContent`'s shape (Enabled/Show Preview/Sound) - no
/// mentions/pinned section here since those aren't reaction-specific concepts.
private struct TelegramReactionNotificationDetailContent: View {
    // MARK: Internal

    let service: any TelegramService
    @State var settings: ReactionNotificationSettings

    let onSaved: (ReactionNotificationSettings) -> Void

    var body: some View {
        Form {
            Section {
                Toggle("Enabled", isOn: enabledBinding)
                Toggle("Show Preview", isOn: showPreviewBinding)
                    .disabled(!settings.isEnabled)
                #if os(iOS)
                    NavigationLink {
                        TelegramNotificationSoundPickerView(
                            service: service,
                            selectedSoundId: settings.soundId,
                        ) { newSoundId in
                            save(settings.withSoundId(newSoundId))
                        }
                    } label: {
                        LabeledContent("Sound", value: soundDisplayName)
                    }
                    .disabled(!settings.isEnabled)
                #else
                    Button {
                        showsSoundPicker = true
                    } label: {
                        LabeledContent("Sound", value: soundDisplayName)
                            .foregroundStyle(.primary)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!settings.isEnabled)
                #endif
            } footer: {
                Text("Notified when someone reacts to your messages or votes in your polls.")
            }
        }
        .task(id: settings.soundId) {
            guard settings.soundId > 0 else {
                soundTitle = nil
                return
            }
            soundTitle = try? await service.getSavedNotificationSound(notificationSoundId: settings.soundId).title
        }
        .alert("Couldn't Update Notification Settings", isPresented: errorIsPresented) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
        #if os(macOS)
        .sheet(isPresented: $showsSoundPicker) {
            TelegramNotificationSoundPickerSheet(service: service, selectedSoundId: settings.soundId) { newSoundId in
                save(settings.withSoundId(newSoundId))
            }
        }
        #endif
    }

    // MARK: Private

    @State private var errorMessage: String?
    @State private var isSaving = false
    #if os(macOS)
    @State private var showsSoundPicker = false
    #endif
    @State private var soundTitle: String?

    private var soundDisplayName: String {
        if settings.soundId <= -1 {
            return "Default"
        }
        if settings.soundId == 0 {
            return "Off"
        }
        return soundTitle ?? "…"
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

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { settings.isEnabled },
            set: { save(settings.withEnabled($0)) },
        )
    }

    private var showPreviewBinding: Binding<Bool> {
        Binding(
            get: { settings.showPreview },
            set: { save(settings.withShowPreview($0)) },
        )
    }

    @MainActor private func save(_ newSettings: ReactionNotificationSettings) {
        guard !isSaving else { return }
        let previousSettings = settings
        settings = newSettings
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                _ = try await service.setReactionNotificationSettings(notificationSettings: newSettings)
                onSaved(newSettings)
            } catch {
                settings = previousSettings
                errorMessage = telegramErrorDescription(error)
            }
        }
    }
}
