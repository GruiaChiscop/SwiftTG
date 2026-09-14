// TelegramNetworkUsageSettings.swift

import SwiftUI
@preconcurrency import TDLibKit

// MARK: - TelegramNetworkUsageCategory

/// Groups TDLib's `FileType` (plus a synthetic `.calls` bucket for `NetworkStatisticsEntryCall`)
/// into the categories Telegram-iOS shows on its own Network Usage screen.
enum TelegramNetworkUsageCategory: CaseIterable, Identifiable {
    case photos
    case videos
    case voiceMessages
    case videoMessages
    case files
    case music
    case stickers
    case animations
    /// Chat/contact avatar images - kept apart from `.photos` because, unlike a photo sent in a
    /// chat, an avatar isn't attached to any message, so TDLib can never attribute it to one chat.
    /// It always lands in the `chatId == 0` "Other Chats" bucket, no matter how high a chat limit
    /// is requested - conflating it with `.photos` reads as "some chat's photos went missing"
    /// when nothing actually went missing.
    case avatars
    case calls
    case other

    // MARK: Lifecycle

    init(fileType: FileType?) {
        self =
            switch fileType {
            case .fileTypePhoto, .fileTypePhotoStory, .fileTypeSelfDestructingPhoto:
                .photos
            case .fileTypeProfilePhoto:
                .avatars
            case .fileTypeLivePhotoVideo, .fileTypeSelfDestructingLivePhotoVideo, .fileTypeSelfDestructingVideo,
                 .fileTypeVideo, .fileTypeVideoStory:
                .videos
            case .fileTypeSelfDestructingVoiceNote, .fileTypeVoiceNote:
                .voiceMessages
            case .fileTypeSelfDestructingVideoNote, .fileTypeVideoNote:
                .videoMessages
            case .fileTypeDocument:
                .files
            case .fileTypeAudio:
                .music
            case .fileTypeSticker:
                .stickers
            case .fileTypeAnimation:
                .animations
            default:
                .other
            }
    }

    // MARK: Internal

    var id: Self { self }

    var title: String {
        switch self {
        case .photos: "Photos"
        case .videos: "Videos"
        case .voiceMessages: "Voice Messages"
        case .videoMessages: "Video Messages"
        case .files: "Files"
        case .music: "Music"
        case .stickers: "Stickers"
        case .animations: "Animations"
        case .avatars: "Profile Photos"
        case .calls: "Calls"
        case .other: "Other"
        }
    }

    /// Fixed per-category so the same category renders identically wherever
    /// `TelegramStorageCategoryChart` draws it - Charts' own `foregroundStyle(by:)` assigns colors
    /// from whichever categories happen to be present in that one chart's data, which would make
    /// e.g. Photos blue on the all-chats chart but red on a chat that lacks some other category.
    var color: Color {
        switch self {
        case .photos: .blue
        case .videos: .purple
        case .voiceMessages: .orange
        case .videoMessages: .pink
        case .files: .green
        case .music: .red
        case .stickers: .yellow
        case .animations: .mint
        case .avatars: .indigo
        case .calls: .teal
        case .other: .gray
        }
    }

    /// The `FileType`s that map to this category, derived from `telegramClearableFileTypes` via
    /// `init(fileType:)` rather than listed by hand, so a clear scoped to selected categories can
    /// never drift out of sync with that grouping.
    var clearableFileTypes: [FileType] {
        telegramClearableFileTypes.filter { Self(fileType: $0) == self }
    }
}

// MARK: - TelegramNetworkUsageScope

enum TelegramNetworkUsageScope: CaseIterable, Identifiable {
    case all
    case wifi
    case mobile

    // MARK: Internal

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "All"
        case .wifi: "Wi-Fi"
        case .mobile: "Mobile"
        }
    }

    /// Roaming (and any network type TDLib can't classify) counts as "Mobile" here, matching
    /// Telegram-iOS's own two-bucket Wi-Fi/Mobile split - it has no separate roaming bucket.
    func matches(_ networkType: NetworkType) -> Bool {
        switch self {
        case .all: true
        case .wifi: networkType == .networkTypeWiFi
        case .mobile: networkType != .networkTypeWiFi
        }
    }
}

// MARK: - TelegramNetworkUsageRow

struct TelegramNetworkUsageRow: Identifiable {
    let category: TelegramNetworkUsageCategory
    let sentBytes: Int64
    let receivedBytes: Int64

    var id: TelegramNetworkUsageCategory { category }
    var totalBytes: Int64 { sentBytes + receivedBytes }
}

// MARK: - TelegramNetworkUsageStore

enum TelegramNetworkUsageStore {
    /// Aggregates `statistics` into one row per category actually present, for network types
    /// `scope` matches, sorted by total bytes descending (largest usage first, mirroring
    /// Telegram-iOS's own ordering).
    static func rows(
        from statistics: NetworkStatistics,
        scope: TelegramNetworkUsageScope,
    ) -> [TelegramNetworkUsageRow] {
        var totals = [TelegramNetworkUsageCategory: (sent: Int64, received: Int64)]()
        for entry in statistics.entries {
            let category: TelegramNetworkUsageCategory
            let networkType: NetworkType
            let sent: Int64
            let received: Int64
            switch entry {
            case .networkStatisticsEntryFile(let file):
                category = TelegramNetworkUsageCategory(fileType: file.fileType)
                networkType = file.networkType
                sent = file.sentBytes
                received = file.receivedBytes
            case .networkStatisticsEntryCall(let call):
                category = .calls
                networkType = call.networkType
                sent = call.sentBytes
                received = call.receivedBytes
            }
            guard scope.matches(networkType) else { continue }
            var totalsForCategory = totals[category] ?? (0, 0)
            totalsForCategory.sent += sent
            totalsForCategory.received += received
            totals[category] = totalsForCategory
        }
        return totals
            .map {
                TelegramNetworkUsageRow(category: $0.key, sentBytes: $0.value.sent, receivedBytes: $0.value.received)
            }
            .sorted { $0.totalBytes > $1.totalBytes }
    }
}

// MARK: - TelegramNetworkUsageView

struct TelegramNetworkUsageView: View {
    // MARK: Lifecycle

    init(service: any TelegramService) {
        self.service = service
    }

    // MARK: Internal

    var body: some View {
        Form {
            Section("Network") {
                Picker("Network", selection: $scope) {
                    ForEach(TelegramNetworkUsageScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if let statistics {
                let rows = TelegramNetworkUsageStore.rows(from: statistics, scope: scope)
                Section {
                    if rows.isEmpty {
                        Text("No data usage recorded yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(rows) { row in
                            LabeledContent(row.category.title, value: formattedBytes(row.totalBytes))
                        }
                    }
                } footer: {
                    Text("Data usage since \(formattedSinceDate(statistics.sinceDate))")
                }

                Section {
                    Button("Reset Statistics", role: .destructive) {
                        confirmsReset = true
                    }
                    .disabled(isWorking)
                }
            } else if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle("Network Usage")
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await load()
        }
        .alert("Reset Network Usage Statistics?", isPresented: $confirmsReset) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) { Task { await reset() } }
        } message: {
            Text("This clears the sent and received byte counters shown here. It doesn't remove any cached files.")
        }
        .alert("Couldn't Load Network Usage", isPresented: errorIsPresented) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Private

    @State private var confirmsReset = false
    @State private var errorMessage: String?
    @State private var hasLoaded = false
    @State private var isLoading = false
    @State private var isWorking = false
    @State private var scope = TelegramNetworkUsageScope.all
    @State private var statistics: NetworkStatistics?

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

    private func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func formattedSinceDate(_ sinceDate: Int) -> String {
        Date(timeIntervalSince1970: TimeInterval(sinceDate))
            .formatted(date: .abbreviated, time: .omitted)
    }

    @MainActor private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            statistics = try await service.getNetworkStatistics(onlyCurrent: false)
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }

    @MainActor private func reset() async {
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await service.resetNetworkStatistics()
            statistics = try await service.getNetworkStatistics(onlyCurrent: false)
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }
}
