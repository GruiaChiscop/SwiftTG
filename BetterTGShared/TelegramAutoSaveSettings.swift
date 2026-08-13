// TelegramAutoSaveSettings.swift

import SwiftUI
@preconcurrency import TDLibKit

// MARK: - TelegramAutoSaveMaxVideoSize

enum TelegramAutoSaveMaxVideoSize: Int64, CaseIterable, Identifiable {
    case halfMB = 524_288 // 512 KB, TDLib's documented minimum
    case oneMB = 1_048_576
    case twoAndHalfMB = 2_621_440
    case fiveMB = 5_242_880
    case tenMB = 10_485_760
    case noLimit = 4_194_304_000 // 4000 MB, TDLib's documented maximum

    // MARK: Lifecycle

    init(closestTo bytes: Int64) {
        self = Self.allCases.min(by: { abs($0.rawValue - bytes) < abs($1.rawValue - bytes) }) ?? .noLimit
    }

    // MARK: Internal

    var id: Int64 { rawValue }

    var title: String {
        switch self {
        case .halfMB: "512 KB"
        case .oneMB: "1 MB"
        case .twoAndHalfMB: "2.5 MB"
        case .fiveMB: "5 MB"
        case .tenMB: "10 MB"
        case .noLimit: "No Limit"
        }
    }
}

// MARK: - TelegramAutoSaveScopeItem

struct TelegramAutoSaveScopeItem: Identifiable {
    let scope: AutosaveSettingsScope
    let title: String

    var id: String { title }
}

let telegramAutoSaveScopeItems: [TelegramAutoSaveScopeItem] = [
    TelegramAutoSaveScopeItem(scope: .autosaveSettingsScopePrivateChats, title: "Private Chats"),
    TelegramAutoSaveScopeItem(scope: .autosaveSettingsScopeGroupChats, title: "Groups"),
    TelegramAutoSaveScopeItem(scope: .autosaveSettingsScopeChannelChats, title: "Channels"),
]

// MARK: - TelegramAutoSaveSettingsView

struct TelegramAutoSaveSettingsView: View {
    // MARK: Lifecycle

    init(service: any TelegramService) {
        self.service = service
    }

    // MARK: Internal

    var body: some View {
        List {
            Section {
                ForEach(telegramAutoSaveScopeItems) { item in
                    #if os(iOS)
                        NavigationLink {
                            TelegramAutoSaveScopeDetailContent(
                                service: service,
                                item: item,
                                settings: settings(for: item.scope),
                            ) { newSettings in
                                setSettings(newSettings, for: item.scope)
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
            } footer: {
                Text("Automatically save incoming photos and videos to your device.")
            }
        }
        .navigationTitle("Auto-Save Media")
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await loadSettings()
        }
        #if os(macOS)
        .sheet(item: $selectedItem) { item in
            TelegramAutoSaveScopeDetailView(
                service: service,
                item: item,
                settings: settings(for: item.scope),
            ) { newSettings in
                setSettings(newSettings, for: item.scope)
            }
        }
        #endif
        .alert("Couldn't Load Auto-Save Settings", isPresented: errorIsPresented) {
                Button("OK") {}
            } message: {
                Text(errorMessage ?? "")
            }
    }

    // MARK: Private

    private static let defaultSettings = ScopeAutosaveSettings(
        autosavePhotos: true,
        autosaveVideos: false,
        maxVideoFileSize: TelegramAutoSaveMaxVideoSize.tenMB.rawValue,
    )

    @State private var errorMessage: String?
    @State private var hasLoaded = false
    #if os(macOS)
    @State private var selectedItem: TelegramAutoSaveScopeItem?
    #endif
    @State private var privateChatSettings: ScopeAutosaveSettings?
    @State private var groupSettings: ScopeAutosaveSettings?
    @State private var channelSettings: ScopeAutosaveSettings?

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

    private func settings(for scope: AutosaveSettingsScope) -> ScopeAutosaveSettings {
        switch scope {
        case .autosaveSettingsScopePrivateChats: privateChatSettings ?? Self.defaultSettings
        case .autosaveSettingsScopeGroupChats: groupSettings ?? Self.defaultSettings
        case .autosaveSettingsScopeChannelChats: channelSettings ?? Self.defaultSettings
        case .autosaveSettingsScopeChat: Self.defaultSettings
        }
    }

    private func setSettings(_ newSettings: ScopeAutosaveSettings, for scope: AutosaveSettingsScope) {
        switch scope {
        case .autosaveSettingsScopePrivateChats: privateChatSettings = newSettings
        case .autosaveSettingsScopeGroupChats: groupSettings = newSettings
        case .autosaveSettingsScopeChannelChats: channelSettings = newSettings
        case .autosaveSettingsScopeChat: break
        }
    }

    private func statusText(for scope: AutosaveSettingsScope) -> String {
        let resolved = settings(for: scope)
        return resolved.autosavePhotos || resolved.autosaveVideos ? "On" : "Off"
    }

    @MainActor private func loadSettings() async {
        do {
            let loaded = try await service.getAutosaveSettings()
            privateChatSettings = loaded.privateChatSettings
            groupSettings = loaded.groupSettings
            channelSettings = loaded.channelSettings
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }
}

// MARK: - TelegramAutoSaveScopeDetailView

#if os(macOS)
private struct TelegramAutoSaveScopeDetailView: View {
    // MARK: Internal

    let service: any TelegramService
    let item: TelegramAutoSaveScopeItem
    let settings: ScopeAutosaveSettings

    let onSaved: (ScopeAutosaveSettings) -> Void

    var body: some View {
        NavigationStack {
            TelegramAutoSaveScopeDetailContent(service: service, item: item, settings: settings, onSaved: onSaved)
                .navigationTitle(item.title)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .frame(minWidth: 360, minHeight: 260)
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
}
#endif

// MARK: - TelegramAutoSaveScopeDetailContent

private struct TelegramAutoSaveScopeDetailContent: View {
    // MARK: Internal

    let service: any TelegramService
    let item: TelegramAutoSaveScopeItem
    @State var settings: ScopeAutosaveSettings

    let onSaved: (ScopeAutosaveSettings) -> Void

    var body: some View {
        Form {
            Section {
                Toggle("Photos", isOn: photosBinding)
                Toggle("Videos", isOn: videosBinding)
                Picker("Maximum Video Size", selection: maxVideoSizeBinding) {
                    ForEach(TelegramAutoSaveMaxVideoSize.allCases) { size in
                        Text(size.title).tag(size)
                    }
                }
                .disabled(!settings.autosaveVideos)
            }
        }
        .alert("Couldn't Update Auto-Save Settings", isPresented: errorIsPresented) {
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

    private var photosBinding: Binding<Bool> {
        Binding(
            get: { settings.autosavePhotos },
            set: { newValue in
                save(ScopeAutosaveSettings(
                    autosavePhotos: newValue,
                    autosaveVideos: settings.autosaveVideos,
                    maxVideoFileSize: settings.maxVideoFileSize,
                ))
            },
        )
    }

    private var videosBinding: Binding<Bool> {
        Binding(
            get: { settings.autosaveVideos },
            set: { newValue in
                save(ScopeAutosaveSettings(
                    autosavePhotos: settings.autosavePhotos,
                    autosaveVideos: newValue,
                    maxVideoFileSize: settings.maxVideoFileSize,
                ))
            },
        )
    }

    private var maxVideoSizeBinding: Binding<TelegramAutoSaveMaxVideoSize> {
        Binding(
            get: { TelegramAutoSaveMaxVideoSize(closestTo: settings.maxVideoFileSize) },
            set: { newValue in
                save(ScopeAutosaveSettings(
                    autosavePhotos: settings.autosavePhotos,
                    autosaveVideos: settings.autosaveVideos,
                    maxVideoFileSize: newValue.rawValue,
                ))
            },
        )
    }

    @MainActor private func save(_ newSettings: ScopeAutosaveSettings) {
        guard !isSaving else { return }
        let previousSettings = settings
        settings = newSettings
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                _ = try await service.setAutosaveSettings(scope: item.scope, settings: newSettings)
                onSaved(newSettings)
            } catch {
                settings = previousSettings
                errorMessage = telegramErrorDescription(error)
            }
        }
    }
}
