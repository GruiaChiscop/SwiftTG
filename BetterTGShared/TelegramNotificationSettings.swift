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

    var playsSound: Bool { soundId != 0 }

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

    func withPlaysSound(_ playsSound: Bool) -> ScopeNotificationSettings {
        ScopeNotificationSettings(
            disableMentionNotifications: disableMentionNotifications,
            disablePinnedMessageNotifications: disablePinnedMessageNotifications,
            muteFor: muteFor,
            muteStories: muteStories,
            showPreview: showPreview,
            showStoryPoster: showStoryPoster,
            soundId: playsSound ? -1 : 0,
            storySoundId: storySoundId,
            useDefaultMuteStories: useDefaultMuteStories,
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
        List(telegramNotificationScopeItems) { item in
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
        .navigationTitle("Notifications")
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await loadSettings()
        }
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
        #endif
        .alert("Couldn't Load Notification Settings", isPresented: errorIsPresented) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Private

    @State private var errorMessage: String?
    @State private var hasLoaded = false
    #if os(macOS)
    @State private var selectedItem: TelegramNotificationScopeItem?
    #endif
    @State private var settings = [NotificationSettingsScope: ScopeNotificationSettings]()

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

    private func statusText(for scope: NotificationSettingsScope) -> String {
        (settings[scope] ?? .defaultSettings).isEnabled ? "On" : "Off"
    }

    @MainActor private func loadSettings() async {
        var resolvedSettings = [NotificationSettingsScope: ScopeNotificationSettings]()
        var loadError: Swift.Error?
        await withTaskGroup(of: (NotificationSettingsScope, Result<ScopeNotificationSettings, Swift.Error>).self) { group in
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
                Toggle("Play Sound", isOn: playsSoundBinding)
                    .disabled(!settings.isEnabled)
            }

            Section {
                Toggle("Mentions as Regular Notifications", isOn: disableMentionBinding)
                Toggle("Pinned Messages as Regular Notifications", isOn: disablePinnedBinding)
            } footer: {
                Text("When on, mentions and pinned messages in this scope no longer stand out from ordinary unread messages.")
            }
        }
        .alert("Couldn't Update Notification Settings", isPresented: errorIsPresented) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Private

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

    private var playsSoundBinding: Binding<Bool> {
        Binding(
            get: { settings.playsSound },
            set: { save(settings.withPlaysSound($0)) },
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
