// TelegramAutoDownloadSettings.swift

import SwiftUI
@preconcurrency import TDLibKit

// MARK: - TelegramAutoDownloadSizeOption

/// TDLib has no getter for the currently-active auto-download settings - the client is expected
/// to own that state. We persist the chosen settings per network type locally (starting from our
/// own defaults, see `TelegramAutoDownloadStore.defaultSettings(for:)`) and push them to TDLib
/// with `setAutoDownloadSettings` whenever they change or the app launches, mirroring how the
/// official clients handle this.
enum TelegramAutoDownloadSizeOption: Int64, CaseIterable, Identifiable, Hashable {
    case off = 0
    case oneMB = 1_048_576
    case fiveMB = 5_242_880
    case tenMB = 10_485_760
    case fiftyMB = 52_428_800
    case hundredMB = 104_857_600
    case unlimited = 1_536_870_912

    // MARK: Internal

    var id: Int64 { rawValue }

    var title: String {
        switch self {
        case .off: "Off"
        case .oneMB: "1 MB"
        case .fiveMB: "5 MB"
        case .tenMB: "10 MB"
        case .fiftyMB: "50 MB"
        case .hundredMB: "100 MB"
        case .unlimited: "No Limit"
        }
    }

    static func closest(to bytes: Int64) -> Self {
        guard bytes > 0 else { return .off }
        return allCases.min(by: { abs($0.rawValue - bytes) < abs($1.rawValue - bytes) }) ?? .unlimited
    }
}

// MARK: - TelegramAutoDownloadNetworkItem

struct TelegramAutoDownloadNetworkItem: Identifiable {
    let type: NetworkType
    let title: String

    var id: String { title }
}

let telegramAutoDownloadNetworkItems: [TelegramAutoDownloadNetworkItem] = [
    TelegramAutoDownloadNetworkItem(type: .networkTypeWiFi, title: "Wi-Fi"),
    TelegramAutoDownloadNetworkItem(type: .networkTypeMobile, title: "Mobile Data"),
    TelegramAutoDownloadNetworkItem(type: .networkTypeMobileRoaming, title: "Roaming"),
]

// MARK: - TelegramAutoDownloadStore

enum TelegramAutoDownloadStore {
    // MARK: Internal

    /// TDLib's own `getAutoDownloadSettingsPresets()` is deliberately not used as a source of
    /// caps: its "high" (Wi-Fi) preset's `maxOtherFileSize` turned out permissive enough to
    /// auto-download several-hundred-MB app installers without a tap, which no reasonable default
    /// should do. Unigram (another TDLib-based client) made the same call - its own "reset to
    /// defaults" action has the equivalent `FromPreset(presets.High)` call commented out in favor
    /// of its own hardcoded numbers: `AutoDownloadSettings.Default` uses a flat 10 MB video / 3 MB
    /// document cap, the same regardless of network type. These match that exactly, rather than
    /// inventing separate (and untested) Wi-Fi/Mobile numbers of our own.
    static func defaultSettings(for type: NetworkType) -> AutoDownloadSettings {
        AutoDownloadSettings(
            isAutoDownloadEnabled: true,
            maxOtherFileSize: 3_145_728,
            maxPhotoFileSize: 1_048_576,
            maxVideoFileSize: 10_485_760,
            preloadLargeVideos: true,
            preloadNextAudio: true,
            preloadStories: true,
            useLessDataForCalls: type != .networkTypeWiFi,
            videoUploadBitrate: 0,
        )
    }

    static func stored(for type: NetworkType) -> AutoDownloadSettings {
        guard
            let data = UserDefaults.standard.data(forKey: defaultsKey(for: type)),
            let decoded = try? JSONDecoder().decode(AutoDownloadSettings.self, from: data)
        else {
            return defaultSettings(for: type)
        }
        return decoded
    }

    static func store(_ settings: AutoDownloadSettings, for type: NetworkType) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey(for: type))
    }

    /// Re-applies the persisted (or default) auto-download settings to TDLib. Call this on
    /// launch, since TDLib doesn't remember the choice across client restarts on its own.
    @MainActor static func applyStored(service: any TelegramService) async {
        for item in telegramAutoDownloadNetworkItems {
            _ = try? await service.setAutoDownloadSettings(settings: stored(for: item.type), type: item.type)
        }
    }

    /// Synchronous lookup for gating a single download decision - message rows call this on every
    /// appearance, so it must not await.
    @MainActor static func effectiveSettings(for type: NetworkType) -> AutoDownloadSettings {
        stored(for: type)
    }

    /// Discards every customization and returns all three network types to our own defaults,
    /// matching Telegram-iOS's "Reset Automatic Media Download Settings" action. Returns the
    /// freshly reset settings so the caller can update its own display without a second fetch.
    @MainActor static func resetToDefaults(service: any TelegramService) async -> [NetworkType: AutoDownloadSettings] {
        var resetSettings = [NetworkType: AutoDownloadSettings]()
        for item in telegramAutoDownloadNetworkItems {
            UserDefaults.standard.removeObject(forKey: defaultsKey(for: item.type))
            let settings = defaultSettings(for: item.type)
            _ = try? await service.setAutoDownloadSettings(settings: settings, type: item.type)
            resetSettings[item.type] = settings
        }
        return resetSettings
    }

    // MARK: Private

    private static func defaultsKey(for type: NetworkType) -> String {
        switch type {
        case .networkTypeWiFi: "BetterTG.autoDownload.wifi"
        case .networkTypeMobile: "BetterTG.autoDownload.mobile"
        case .networkTypeMobileRoaming: "BetterTG.autoDownload.roaming"
        case .networkTypeNone, .networkTypeOther: "BetterTG.autoDownload.other"
        }
    }
}

// MARK: - TelegramAutoDownloadSettingsView

struct TelegramAutoDownloadSettingsView: View {
    // MARK: Lifecycle

    init(service: any TelegramService) {
        self.service = service
    }

    // MARK: Internal

    var body: some View {
        List {
            Section {
                ForEach(telegramAutoDownloadNetworkItems) { item in
                    Button {
                        selectedItem = item
                    } label: {
                        LabeledContent(item.title, value: statusText(for: item.type))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Section {
                Button("Reset Automatic Media Download Settings", role: .destructive) {
                    confirmsReset = true
                }
                .disabled(isResetting)
            }
        }
        .navigationTitle("Automatic Download")
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            loadSettings()
        }
        .sheet(item: $selectedItem) { item in
            TelegramAutoDownloadDetailView(
                service: service,
                item: item,
                settings: settings[item.type] ?? TelegramAutoDownloadStore.defaultSettings(for: item.type),
            ) { newSettings in
                settings[item.type] = newSettings
            }
        }
        .alert("Reset Automatic Media Download Settings?", isPresented: $confirmsReset) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) { Task { await resetToDefaults() } }
        } message: {
            Text("This discards any custom size limits or toggles you've set for Wi-Fi, Mobile Data, and Roaming.")
        }
    }

    // MARK: Private

    @State private var confirmsReset = false
    @State private var hasLoaded = false
    @State private var isResetting = false
    @State private var selectedItem: TelegramAutoDownloadNetworkItem?
    @State private var settings = [NetworkType: AutoDownloadSettings]()

    private let service: any TelegramService

    private func statusText(for type: NetworkType) -> String {
        (settings[type]?.isAutoDownloadEnabled ?? true) ? "On" : "Off"
    }

    @MainActor private func loadSettings() {
        var resolvedSettings = [NetworkType: AutoDownloadSettings]()
        for item in telegramAutoDownloadNetworkItems {
            resolvedSettings[item.type] = TelegramAutoDownloadStore.stored(for: item.type)
        }
        settings = resolvedSettings
    }

    @MainActor private func resetToDefaults() async {
        isResetting = true
        defer { isResetting = false }
        settings = await TelegramAutoDownloadStore.resetToDefaults(service: service)
    }
}

// MARK: - TelegramAutoDownloadDetailView

private struct TelegramAutoDownloadDetailView: View {
    // MARK: Internal

    let service: any TelegramService
    let item: TelegramAutoDownloadNetworkItem
    @State var settings: AutoDownloadSettings?

    let onSaved: (AutoDownloadSettings) -> Void

    var body: some View {
        NavigationStack {
            Form {
                if let settings {
                    Section {
                        Toggle("Auto-Download Media", isOn: enabledBinding(settings))
                    }

                    Section("Limit By File Size") {
                        Picker("Photos", selection: photoSizeBinding(settings)) {
                            optionRows
                        }
                        Picker("Videos", selection: videoSizeBinding(settings)) {
                            optionRows
                        }
                        Picker("Files", selection: otherSizeBinding(settings)) {
                            optionRows
                        }
                    }
                    .disabled(!settings.isAutoDownloadEnabled)

                    Section {
                        Toggle("Preload Larger Videos", isOn: preloadLargeVideosBinding(settings))
                        Toggle("Preload Next Voice Track", isOn: preloadNextAudioBinding(settings))
                        Toggle("Preload Stories", isOn: preloadStoriesBinding(settings))
                        Toggle("Use Less Data For Calls", isOn: useLessDataForCallsBinding(settings))
                    }
                    .disabled(!settings.isAutoDownloadEnabled)
                } else {
                    ProgressView()
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
        .frame(minWidth: 380, minHeight: 420)
        #endif
        .alert("Couldn't Update Auto-Download Settings", isPresented: errorIsPresented) {
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

    private var optionRows: some View {
        ForEach(TelegramAutoDownloadSizeOption.allCases) { option in
            Text(option.title).tag(option)
        }
    }

    private func enabledBinding(_ settings: AutoDownloadSettings) -> Binding<Bool> {
        Binding(
            get: { settings.isAutoDownloadEnabled },
            set: { save(settings.withEnabled($0)) },
        )
    }

    private func photoSizeBinding(_ settings: AutoDownloadSettings) -> Binding<TelegramAutoDownloadSizeOption> {
        Binding(
            get: { .closest(to: Int64(settings.maxPhotoFileSize)) },
            set: { save(settings.withMaxPhotoFileSize($0.rawValue)) },
        )
    }

    private func videoSizeBinding(_ settings: AutoDownloadSettings) -> Binding<TelegramAutoDownloadSizeOption> {
        Binding(
            get: { .closest(to: settings.maxVideoFileSize) },
            set: { save(settings.withMaxVideoFileSize($0.rawValue)) },
        )
    }

    private func otherSizeBinding(_ settings: AutoDownloadSettings) -> Binding<TelegramAutoDownloadSizeOption> {
        Binding(
            get: { .closest(to: settings.maxOtherFileSize) },
            set: { save(settings.withMaxOtherFileSize($0.rawValue)) },
        )
    }

    private func preloadLargeVideosBinding(_ settings: AutoDownloadSettings) -> Binding<Bool> {
        Binding(
            get: { settings.preloadLargeVideos },
            set: { save(settings.withPreloadLargeVideos($0)) },
        )
    }

    private func preloadNextAudioBinding(_ settings: AutoDownloadSettings) -> Binding<Bool> {
        Binding(
            get: { settings.preloadNextAudio },
            set: { save(settings.withPreloadNextAudio($0)) },
        )
    }

    private func preloadStoriesBinding(_ settings: AutoDownloadSettings) -> Binding<Bool> {
        Binding(
            get: { settings.preloadStories },
            set: { save(settings.withPreloadStories($0)) },
        )
    }

    private func useLessDataForCallsBinding(_ settings: AutoDownloadSettings) -> Binding<Bool> {
        Binding(
            get: { settings.useLessDataForCalls },
            set: { save(settings.withUseLessDataForCalls($0)) },
        )
    }

    @MainActor private func save(_ newSettings: AutoDownloadSettings) {
        guard !isSaving else { return }
        let previousSettings = settings
        settings = newSettings
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                _ = try await service.setAutoDownloadSettings(settings: newSettings, type: item.type)
                TelegramAutoDownloadStore.store(newSettings, for: item.type)
                onSaved(newSettings)
            } catch {
                settings = previousSettings
                errorMessage = telegramErrorDescription(error)
            }
        }
    }
}

extension AutoDownloadSettings {
    func withEnabled(_ isAutoDownloadEnabled: Bool) -> AutoDownloadSettings {
        AutoDownloadSettings(
            isAutoDownloadEnabled: isAutoDownloadEnabled,
            maxOtherFileSize: maxOtherFileSize,
            maxPhotoFileSize: maxPhotoFileSize,
            maxVideoFileSize: maxVideoFileSize,
            preloadLargeVideos: preloadLargeVideos,
            preloadNextAudio: preloadNextAudio,
            preloadStories: preloadStories,
            useLessDataForCalls: useLessDataForCalls,
            videoUploadBitrate: videoUploadBitrate,
        )
    }

    func withMaxPhotoFileSize(_ bytes: Int64) -> AutoDownloadSettings {
        AutoDownloadSettings(
            isAutoDownloadEnabled: isAutoDownloadEnabled,
            maxOtherFileSize: maxOtherFileSize,
            maxPhotoFileSize: Int(clamping: bytes),
            maxVideoFileSize: maxVideoFileSize,
            preloadLargeVideos: preloadLargeVideos,
            preloadNextAudio: preloadNextAudio,
            preloadStories: preloadStories,
            useLessDataForCalls: useLessDataForCalls,
            videoUploadBitrate: videoUploadBitrate,
        )
    }

    func withMaxVideoFileSize(_ bytes: Int64) -> AutoDownloadSettings {
        AutoDownloadSettings(
            isAutoDownloadEnabled: isAutoDownloadEnabled,
            maxOtherFileSize: maxOtherFileSize,
            maxPhotoFileSize: maxPhotoFileSize,
            maxVideoFileSize: bytes,
            preloadLargeVideos: preloadLargeVideos,
            preloadNextAudio: preloadNextAudio,
            preloadStories: preloadStories,
            useLessDataForCalls: useLessDataForCalls,
            videoUploadBitrate: videoUploadBitrate,
        )
    }

    func withMaxOtherFileSize(_ bytes: Int64) -> AutoDownloadSettings {
        AutoDownloadSettings(
            isAutoDownloadEnabled: isAutoDownloadEnabled,
            maxOtherFileSize: bytes,
            maxPhotoFileSize: maxPhotoFileSize,
            maxVideoFileSize: maxVideoFileSize,
            preloadLargeVideos: preloadLargeVideos,
            preloadNextAudio: preloadNextAudio,
            preloadStories: preloadStories,
            useLessDataForCalls: useLessDataForCalls,
            videoUploadBitrate: videoUploadBitrate,
        )
    }

    func withPreloadLargeVideos(_ preloadLargeVideos: Bool) -> AutoDownloadSettings {
        AutoDownloadSettings(
            isAutoDownloadEnabled: isAutoDownloadEnabled,
            maxOtherFileSize: maxOtherFileSize,
            maxPhotoFileSize: maxPhotoFileSize,
            maxVideoFileSize: maxVideoFileSize,
            preloadLargeVideos: preloadLargeVideos,
            preloadNextAudio: preloadNextAudio,
            preloadStories: preloadStories,
            useLessDataForCalls: useLessDataForCalls,
            videoUploadBitrate: videoUploadBitrate,
        )
    }

    func withPreloadNextAudio(_ preloadNextAudio: Bool) -> AutoDownloadSettings {
        AutoDownloadSettings(
            isAutoDownloadEnabled: isAutoDownloadEnabled,
            maxOtherFileSize: maxOtherFileSize,
            maxPhotoFileSize: maxPhotoFileSize,
            maxVideoFileSize: maxVideoFileSize,
            preloadLargeVideos: preloadLargeVideos,
            preloadNextAudio: preloadNextAudio,
            preloadStories: preloadStories,
            useLessDataForCalls: useLessDataForCalls,
            videoUploadBitrate: videoUploadBitrate,
        )
    }

    func withPreloadStories(_ preloadStories: Bool) -> AutoDownloadSettings {
        AutoDownloadSettings(
            isAutoDownloadEnabled: isAutoDownloadEnabled,
            maxOtherFileSize: maxOtherFileSize,
            maxPhotoFileSize: maxPhotoFileSize,
            maxVideoFileSize: maxVideoFileSize,
            preloadLargeVideos: preloadLargeVideos,
            preloadNextAudio: preloadNextAudio,
            preloadStories: preloadStories,
            useLessDataForCalls: useLessDataForCalls,
            videoUploadBitrate: videoUploadBitrate,
        )
    }

    func withUseLessDataForCalls(_ useLessDataForCalls: Bool) -> AutoDownloadSettings {
        AutoDownloadSettings(
            isAutoDownloadEnabled: isAutoDownloadEnabled,
            maxOtherFileSize: maxOtherFileSize,
            maxPhotoFileSize: maxPhotoFileSize,
            maxVideoFileSize: maxVideoFileSize,
            preloadLargeVideos: preloadLargeVideos,
            preloadNextAudio: preloadNextAudio,
            preloadStories: preloadStories,
            useLessDataForCalls: useLessDataForCalls,
            videoUploadBitrate: videoUploadBitrate,
        )
    }
}
