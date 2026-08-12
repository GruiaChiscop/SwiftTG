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

// MARK: - TelegramStorageSettingsView

struct TelegramStorageSettingsView: View {
    // MARK: Lifecycle

    init(service: any TelegramService) {
        self.service = service
    }

    // MARK: Internal

    var body: some View {
        Form {
            Section("Storage Usage") {
                LabeledContent("Cached media", value: formattedCacheSize)
                LabeledContent("Cached files", value: "\(cachedFileCount)")

                Button("Clear Cache", role: .destructive) {
                    confirmsCacheClear = true
                }
                .disabled(isWorking || cachedFileCount == 0)
            }

            Section {
                #if os(iOS)
                    NavigationLink {
                        TelegramAutoDownloadSettingsView(service: service)
                    } label: {
                        Label("Automatic Media Download", systemImage: "arrow.down.circle")
                    }
                #else
                    Button {
                        presentedDataSetting = .automaticMediaDownload
                    } label: {
                        Label("Automatic Media Download", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                #endif
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
            await TelegramKeepMediaPolicy.applyStoredPolicy(service: service)
            await TelegramAutoDownloadStore.applyStored(service: service)
            await proxyStatusStore.refresh(service: service)
            await refreshStatistics()
            await loadSensitiveContentOptions()
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
        case proxy

        // MARK: Internal

        var id: Self { self }
    }

    @ViewBuilder private func dataSettingDestination(_ item: DataSetting) -> some View {
        switch item {
        case .automaticMediaDownload:
            TelegramAutoDownloadSettingsView(service: service)
        case .proxy:
            TelegramProxySettingsView(service: service)
        }
    }
    #endif

    private static let clearableFileTypes: [FileType] = [
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

    @AppStorage(TelegramKeepMediaPolicy.defaultsKey) private var keepMediaDays = TelegramKeepMediaPolicy.forever
        .rawValue
    @State private var cachedFileCount = 0
    @State private var cachedFilesSize: Int64 = 0
    @State private var canIgnoreSensitiveContentRestrictions = false
    @State private var confirmsCacheClear = false
    @State private var errorMessage: String?
    @State private var ignoresSensitiveContentRestrictions = false
    @State private var isSavingSensitiveContent = false
    @State private var isWorking = false
    @State private var workingLabel = "Calculating storage usage…"
    #if os(macOS)
    @State private var presentedDataSetting: DataSetting?
    #endif

    private let service: any TelegramService
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
        isWorking = true
        workingLabel = "Calculating storage usage…"
        defer { isWorking = false }
        do {
            let statistics = try await service.getStorageStatisticsFast()
            cachedFilesSize = statistics.filesSize
            cachedFileCount = statistics.fileCount
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
                fileTypes: Self.clearableFileTypes,
                immunityDelay: 0,
                returnDeletedFileStatistics: false,
                size: Int64.max,
                ttl: 0,
            )
            let statistics = try await service.getStorageStatisticsFast()
            cachedFilesSize = statistics.filesSize
            cachedFileCount = statistics.fileCount
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }
}
