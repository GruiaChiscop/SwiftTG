// TelegramStorageManagement.swift

import SwiftUI
import TDLibKit

// MARK: - TelegramKeepMediaPolicy

enum TelegramKeepMediaPolicy: Int, CaseIterable, Identifiable {
    case threeDays = 3
    case oneWeek = 7
    case oneMonth = 30
    case forever = 0

    // MARK: Internal

    static let defaultsKey = "BetterTG.keepMediaDays"

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .threeDays: "3 days"
        case .oneWeek: "1 week"
        case .oneMonth: "1 month"
        case .forever: "Forever"
        }
    }

    static func stored() -> Self {
        Self(rawValue: UserDefaults.standard.integer(forKey: defaultsKey)) ?? .forever
    }

    static func applyStoredPolicy(service: any TelegramService) async {
        try? await stored().apply(service: service)
    }

    func apply(service: any TelegramService) async throws {
        if self == .forever {
            _ = try await service.setOption(
                name: "use_storage_optimizer",
                value: .optionValueBoolean(OptionValueBoolean(value: false)),
            )
        } else {
            let seconds = Int64(rawValue * 24 * 60 * 60)
            _ = try await service.setOption(
                name: "storage_max_time_from_last_access",
                value: .optionValueInteger(OptionValueInteger(value: TdInt64(seconds))),
            )
            _ = try await service.setOption(
                name: "use_storage_optimizer",
                value: .optionValueBoolean(OptionValueBoolean(value: true)),
            )
        }
    }
}

/// File types `optimizeStorage`/`clearCache` are allowed to remove from the local cache. Shared by
/// the aggregate "Clear Cache" action and the per-chat clear action in `TelegramStorageUsageView`.
let telegramClearableFileTypes: [FileType] = [
    .fileTypeAnimation,
    .fileTypeAudio,
    .fileTypeDocument,
    .fileTypeLivePhotoVideo,
    .fileTypeNotificationSound,
    .fileTypePhoto,
    .fileTypePhotoStory,
    .fileTypeProfilePhoto,
    .fileTypeSecret,
    .fileTypeSecretThumbnail,
    .fileTypeSecure,
    .fileTypeSelfDestructingLivePhotoVideo,
    .fileTypeSelfDestructingPhoto,
    .fileTypeSelfDestructingVideo,
    .fileTypeSelfDestructingVideoNote,
    .fileTypeSelfDestructingVoiceNote,
    .fileTypeSticker,
    .fileTypeThumbnail,
    .fileTypeUnknown,
    .fileTypeVideo,
    .fileTypeVideoNote,
    .fileTypeVideoStory,
    .fileTypeVoiceNote,
    .fileTypeWallpaper,
]

// MARK: - TelegramStorageSettingsView

struct TelegramStorageSettingsView: View {
    // MARK: Lifecycle

    init(service: any TelegramService, sharedMediaDestination: ((Int64, String) -> AnyView)? = nil) {
        self.service = service
        self.sharedMediaDestination = sharedMediaDestination
    }

    // MARK: Internal

    var body: some View {
        Form {
            Section("Storage Usage") {
                if hasLoadedStatistics {
                    LabeledContent("Cached media", value: formattedCacheSize)
                    LabeledContent("Cached files", value: "\(cachedFileCount)")
                    LabeledContent("Database", value: formattedDatabaseSize)

                    #if os(iOS)
                        NavigationLink {
                            TelegramStorageUsageView(service: service, sharedMediaDestination: sharedMediaDestination)
                        } label: {
                            Label("View by Chat", systemImage: "list.bullet")
                        }
                    #else
                        Button {
                            presentedDataSetting = .storageByChat
                        } label: {
                            Label("View by Chat", systemImage: "list.bullet")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.primary)
                    #endif

                    Button("Clear Cache", role: .destructive) {
                        confirmsCacheClear = true
                    }
                    .disabled(isWorking || cachedFileCount == 0)
                } else {
                    HStack {
                        Spacer()
                        ProgressView("Calculating Storage Usage…")
                        Spacer()
                    }
                }
            }

            Section {
                #if os(iOS)
                    NavigationLink {
                        TelegramNetworkUsageView(service: service)
                    } label: {
                        Label("Network Usage", systemImage: "chart.bar")
                    }
                #else
                    Button {
                        presentedDataSetting = .networkUsage
                    } label: {
                        Label("Network Usage", systemImage: "chart.bar")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                #endif
            }

            Section {
                #if os(iOS)
                    NavigationLink {
                        TelegramAutoDownloadSettingsView(service: service)
                    } label: {
                        Label("Automatic Media Download", systemImage: "arrow.down.circle")
                    }
                    NavigationLink {
                        TelegramAutoSaveSettingsView(service: service)
                    } label: {
                        Label("Auto-Save Media", systemImage: "square.and.arrow.down")
                    }
                #else
                    Button {
                        presentedDataSetting = .automaticMediaDownload
                    } label: {
                        Label("Automatic Media Download", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    Button {
                        presentedDataSetting = .autoSaveMedia
                    } label: {
                        Label("Auto-Save Media", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                #endif
            }

            Section {
                Picker("Use Less Data for Calls", selection: $callDataSaving) {
                    ForEach(TelegramCallDataSaving.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
            } footer: {
                Text(
                    "Using less data may improve your experience on bad networks, but will slightly decrease audio quality.",
                )
            }

            Section("Keep Media") {
                Picker("Keep Media", selection: $keepMediaDays) {
                    ForEach(TelegramKeepMediaPolicy.allCases) { policy in
                        Text(policy.title).tag(policy.rawValue)
                    }
                }

                Text(
                    "Media that you haven't accessed during this period will be removed from the TDLib cache. Files saved in Downloads or with Save As aren't affected.",
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            if canIgnoreSensitiveContentRestrictions {
                Section {
                    Toggle("Sensitive Content", isOn: sensitiveContentBinding)
                        .disabled(isSavingSensitiveContent)
                } footer: {
                    Text("Show media that's flagged as sensitive without a spoiler overlay.")
                }
            }

            #if os(iOS)
                Section {
                    Toggle("Pause Music While Recording", isOn: $pauseMusicWhileRecording)
                    Toggle("Raise to Listen", isOn: $raiseToListen)
                } footer: {
                    Text(
                        "Pause Music While Recording stops other audio from playing while you record a video message. Raise to Listen switches a playing voice message to the earpiece when you hold the phone to your ear.",
                    )
                }
            #endif

            Section("Connection Type") {
                #if os(iOS)
                    NavigationLink {
                        TelegramProxySettingsView(service: service)
                    } label: {
                        LabeledContent("Proxy", value: proxyStatusStore.shortcutStatus?.value ?? "None")
                    }
                #else
                    Button {
                        presentedDataSetting = .proxy
                    } label: {
                        LabeledContent("Proxy", value: proxyStatusStore.shortcutStatus?.value ?? "None")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                #endif
            }

            if isWorking {
                Section {
                    ProgressView(workingLabel)
                }
            }
        }
        .navigationTitle("Data and Storage")
        .task {
            // None of these depend on one another - run them concurrently so the storage
            // calculation (the only one with a dedicated loading state below) starts immediately
            // instead of sitting queued behind unrelated work.
            async let keepMediaPolicy: () = TelegramKeepMediaPolicy.applyStoredPolicy(service: service)
            async let autoDownloadSettings: () = TelegramAutoDownloadStore.applyStored(service: service)
            async let proxyStatus: () = proxyStatusStore.refresh(service: service)
            async let statistics: () = refreshStatistics()
            async let sensitiveContentOptions: () = loadSensitiveContentOptions()
            _ = await (keepMediaPolicy, autoDownloadSettings, proxyStatus, statistics, sensitiveContentOptions)
        }
        .onChange(of: keepMediaDays) { _, newValue in
            guard let policy = TelegramKeepMediaPolicy(rawValue: newValue) else { return }
            Task { await apply(policy) }
        }
        .alert("Clear Cache?", isPresented: $confirmsCacheClear) {
            Button("Clear Cache", role: .destructive) {
                Task { await clearCache() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Cached media will be removed. Files saved in Downloads or with Save As will remain available.")
        }
        .alert("Storage operation failed", isPresented: errorIsPresented) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
        #if os(macOS)
        .sheet(item: $presentedDataSetting) { item in
            NavigationStack {
                dataSettingDestination(item)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { presentedDataSetting = nil }
                        }
                    }
            }
            .frame(minWidth: 440, minHeight: 420)
        }
        #endif
    }

    // MARK: Private

    #if os(macOS)
    private enum DataSetting: String, Identifiable {
        case automaticMediaDownload
        case autoSaveMedia
        case networkUsage
        case proxy
        case storageByChat

        // MARK: Internal

        var id: Self { self }
    }

    @ViewBuilder private func dataSettingDestination(_ item: DataSetting) -> some View {
        switch item {
        case .automaticMediaDownload:
            TelegramAutoDownloadSettingsView(service: service)
        case .autoSaveMedia:
            TelegramAutoSaveSettingsView(service: service)
        case .networkUsage:
            TelegramNetworkUsageView(service: service)
        case .proxy:
            TelegramProxySettingsView(service: service)
        case .storageByChat:
            TelegramStorageUsageView(service: service)
        }
    }
    #endif

    @AppStorage(TelegramKeepMediaPolicy.defaultsKey) private var keepMediaDays = TelegramKeepMediaPolicy.forever
        .rawValue
    @AppStorage(TelegramCallSettings.dataSavingDefaultsKey) private var callDataSaving = TelegramCallSettings
        .dataSaving
    #if os(iOS)
        @AppStorage(TelegramPauseMusicSetting.defaultsKey) private var pauseMusicWhileRecording = true
        @AppStorage(TelegramRaiseToListenSetting.defaultsKey) private var raiseToListen = false
    #endif
    @State private var cachedFileCount = 0
    @State private var cachedFilesSize: Int64 = 0
    @State private var databaseSize: Int64 = 0
    @State private var hasLoadedStatistics = false
    @State private var canIgnoreSensitiveContentRestrictions = false
    @State private var confirmsCacheClear = false
    @State private var errorMessage: String?
    @State private var ignoresSensitiveContentRestrictions = false
    @State private var isSavingSensitiveContent = false
    @State private var isWorking = false
    @State private var workingLabel = "Working…"
    #if os(macOS)
    @State private var presentedDataSetting: DataSetting?
    #endif

    private let service: any TelegramService
    private let sharedMediaDestination: ((Int64, String) -> AnyView)?
    private let proxyStatusStore = TelegramProxyStatusStore.shared

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

    private var formattedCacheSize: String {
        ByteCountFormatter.string(fromByteCount: cachedFilesSize, countStyle: .file)
    }

    /// TDLib's own approximate figure for the local database (`getStorageStatisticsFast`) - the
    /// message/chat store on disk, separate from the media cache above.
    private var formattedDatabaseSize: String {
        ByteCountFormatter.string(fromByteCount: databaseSize, countStyle: .file)
    }

    private var sensitiveContentBinding: Binding<Bool> {
        Binding(
            get: { ignoresSensitiveContentRestrictions },
            set: { newValue in
                let previousValue = ignoresSensitiveContentRestrictions
                ignoresSensitiveContentRestrictions = newValue
                isSavingSensitiveContent = true
                Task {
                    defer { isSavingSensitiveContent = false }
                    do {
                        _ = try await service.setOption(
                            name: "ignore_sensitive_content_restrictions",
                            value: .optionValueBoolean(OptionValueBoolean(value: newValue)),
                        )
                    } catch {
                        ignoresSensitiveContentRestrictions = previousValue
                        errorMessage = telegramErrorDescription(error)
                    }
                }
            },
        )
    }

    @MainActor private func loadSensitiveContentOptions() async {
        guard case .optionValueBoolean(let canIgnore) = try? await service.getOption(
            name: "can_ignore_sensitive_content_restrictions",
        ) else { return }
        canIgnoreSensitiveContentRestrictions = canIgnore.value
        guard canIgnore.value, case .optionValueBoolean(let ignores) = try? await service.getOption(
            name: "ignore_sensitive_content_restrictions",
        ) else { return }
        ignoresSensitiveContentRestrictions = ignores.value
    }

    @MainActor private func apply(_ policy: TelegramKeepMediaPolicy) async {
        do {
            try await policy.apply(service: service)
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }

    @MainActor private func refreshStatistics() async {
        // Its own inline "Calculating Storage Usage…" placeholder covers this load - not the
        // shared `isWorking` banner at the bottom of the form, which would otherwise show
        // alongside it and say the same thing twice.
        defer { hasLoadedStatistics = true }
        do {
            let statistics = try await service.getStorageStatisticsFast()
            cachedFilesSize = statistics.filesSize
            cachedFileCount = statistics.fileCount
            databaseSize = statistics.databaseSize
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }

    @MainActor private func clearCache() async {
        isWorking = true
        workingLabel = "Clearing cache…"
        defer { isWorking = false }
        do {
            _ = try await service.optimizeStorage(
                chatIds: [],
                chatLimit: 25,
                count: Int(Int32.max),
                excludeChatIds: [],
                fileTypes: telegramClearableFileTypes,
                immunityDelay: 0,
                returnDeletedFileStatistics: false,
                size: Int64.max,
                ttl: 0,
            )
            let statistics = try await service.getStorageStatisticsFast()
            cachedFilesSize = statistics.filesSize
            cachedFileCount = statistics.fileCount
            databaseSize = statistics.databaseSize
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }
}
