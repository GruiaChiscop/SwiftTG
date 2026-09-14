// TelegramStorageUsageView.swift

import Charts
import SwiftUI
@preconcurrency import TDLibKit

// MARK: - TelegramStorageUsageChatRow

struct TelegramStorageUsageChatRow: Identifiable {
    let chatId: Int64
    let title: String
    let stats: StorageStatisticsByChat

    var id: Int64 { chatId }
}

// MARK: - TelegramStorageUsageStore

enum TelegramStorageUsageStore {
    // MARK: Internal

    /// Chats beyond `getStorageStatistics`'s `chatLimit` are folded into one anonymous
    /// `chatId == 0` entry - dropped here rather than shown as an opaque "Other Chats" row,
    /// matching Unigram (another TDLib-based client): a real chat in there becomes its own row
    /// once `chatLimit` grows enough (see "Load More"), and anything left over is Profile Photos,
    /// which the category breakdown above already reports on its own.
    static func resolveRows(
        byChat: [StorageStatisticsByChat],
        service: any TelegramService,
    ) async -> [TelegramStorageUsageChatRow] {
        await withTaskGroup(of: TelegramStorageUsageChatRow.self) { group in
            for stats in byChat where stats.chatId != 0 {
                group.addTask {
                    let title = await (try? service.getChat(chatId: stats.chatId))?.title ?? "Unknown Chat"
                    return TelegramStorageUsageChatRow(chatId: stats.chatId, title: title, stats: stats)
                }
            }
            var rows = [TelegramStorageUsageChatRow]()
            for await row in group {
                rows.append(row)
            }
            return rows.sorted { $0.stats.size > $1.stats.size }
        }
    }

    /// Groups a chat's `byFileType` breakdown into the same categories `TelegramNetworkUsageView`
    /// uses, so the two screens read consistently.
    static func categoryRows(byFileType: [StorageStatisticsByFileType]) -> [(
        category: TelegramNetworkUsageCategory,
        size: Int64,
        count: Int,
    )] {
        var totals = [TelegramNetworkUsageCategory: (size: Int64, count: Int)]()
        for entry in byFileType {
            let category = TelegramNetworkUsageCategory(fileType: entry.fileType)
            var totalForCategory = totals[category] ?? (0, 0)
            totalForCategory.size += entry.size
            totalForCategory.count += entry.count
            totals[category] = totalForCategory
        }
        return totals
            .map { (category: $0.key, size: $0.value.size, count: $0.value.count) }
            .sorted { $0.size > $1.size }
    }

    /// The chart never shows a folded "Other" slice while expanded - at that point every category
    /// already has its own row, so a combined slice would double-count that portion of the pie.
    static func chartEntries(
        from categoryRows: [(category: TelegramNetworkUsageCategory, size: Int64, count: Int)],
        isOtherExpanded: Bool,
    ) -> [TelegramStorageDisplayEntry] {
        guard categoryRows.count > maxIndividualCategories, !isOtherExpanded else {
            return categoryRows.map { .category($0.category, size: $0.size, count: $0.count) }
        }
        let shown = categoryRows.prefix(maxIndividualCategories)
        let folded = categoryRows.dropFirst(maxIndividualCategories)
        var entries = shown.map { TelegramStorageDisplayEntry.category($0.category, size: $0.size, count: $0.count) }
        entries.append(.grouped(
            categories: folded.map(\.category),
            size: folded.reduce(0) { $0 + $1.size },
            count: folded.reduce(0) { $0 + $1.count },
        ))
        return entries
    }

    /// Splits into what always shows individually and what folds under a `DisclosureGroup` - the
    /// list (unlike the chart) leans on that native control for the "Other" row instead of a
    /// hand-rolled one, so expand/collapse behavior and its VoiceOver state announcement both come
    /// from the system for free instead of being reimplemented.
    static func splitForDisplay(
        _ categoryRows: [(category: TelegramNetworkUsageCategory, size: Int64, count: Int)],
    ) -> (
        shown: [(category: TelegramNetworkUsageCategory, size: Int64, count: Int)],
        folded: [(category: TelegramNetworkUsageCategory, size: Int64, count: Int)],
    ) {
        guard categoryRows.count > maxIndividualCategories else {
            return (categoryRows, [])
        }
        return (
            Array(categoryRows.prefix(maxIndividualCategories)),
            Array(categoryRows.dropFirst(maxIndividualCategories)),
        )
    }

    // MARK: Private

    /// Telegram-iOS's own Storage Usage chart caps individually-shown categories at 5, folding
    /// the rest into one "Other" slice.
    private static let maxIndividualCategories = 5
}

// MARK: - TelegramStorageDisplayEntry

/// One slice shown in the chart - either a real category, or the small-categories fold
/// Telegram-iOS calls "Other". Tapping a `.grouped` slice expands it (via `onTapGrouped`) instead
/// of selecting it, matching `StorageCategoriesComponent`'s own action: expand if it has
/// subcategories, otherwise toggle selection. The list below the chart doesn't use this type - it
/// renders folded categories with a native `DisclosureGroup` instead (see
/// `TelegramStorageUsageStore.splitForDisplay`).
enum TelegramStorageDisplayEntry: Identifiable {
    case category(TelegramNetworkUsageCategory, size: Int64, count: Int)
    case grouped(categories: [TelegramNetworkUsageCategory], size: Int64, count: Int)

    // MARK: Internal

    var id: String {
        switch self {
        case .category(let category, _, _): "category-\(category)"
        case .grouped: "grouped"
        }
    }

    var title: String {
        switch self {
        case .category(let category, _, _): category.title
        case .grouped: "Other"
        }
    }

    var size: Int64 {
        switch self {
        case .category(_, let size, _): size
        case .grouped(_, let size, _): size
        }
    }

    var color: Color {
        switch self {
        case .category(let category, _, _): category.color
        case .grouped: .gray
        }
    }
}

// MARK: - TelegramStorageCategorySelection

/// Multi-select state for the category chart/list, mirroring Telegram-iOS exactly - which
/// deliberately keeps two different notions of "selected" apart:
/// - `isSelected`: has this category been explicitly tapped? Drives the row's checkmark. An empty
///   selection means nothing shows as checked yet, even though everything still counts below.
/// - `isIncluded`: does this category count toward the running total, the chart's fade, and a
///   "Clear" action? An empty selection means everything does (nothing has been narrowed down).
/// Conflating the two (an earlier version of this type did) makes a single tapped-then-untapped
/// category always read back as "selected", since removing it from an otherwise-empty set just
/// returns to the empty-means-everything state.
struct TelegramStorageCategorySelection: Equatable {
    private(set) var categories = Set<TelegramNetworkUsageCategory>()

    func isSelected(_ category: TelegramNetworkUsageCategory) -> Bool {
        categories.contains(category)
    }

    func isIncluded(_ category: TelegramNetworkUsageCategory) -> Bool {
        categories.isEmpty || categories.contains(category)
    }

    mutating func toggle(_ category: TelegramNetworkUsageCategory) {
        if categories.contains(category) {
            categories.remove(category)
        } else {
            categories.insert(category)
        }
    }

    func totalSize(in categoryRows: [(category: TelegramNetworkUsageCategory, size: Int64, count: Int)]) -> Int64 {
        categoryRows.filter { isIncluded($0.category) }.reduce(0) { $0 + $1.size }
    }

    func fileTypes(in categoryRows: [(category: TelegramNetworkUsageCategory, size: Int64, count: Int)]) -> [FileType] {
        categoryRows.filter { isIncluded($0.category) }.flatMap(\.category.clearableFileTypes)
    }
}

// MARK: - TelegramStorageCategoryChart

/// A donut chart of category sizes, mirroring Telegram-iOS's own Storage Usage header chart:
/// unselected categories fade, each slice carries its own percentage label, the center of the
/// donut hole shows the running total, and tapping a slice directly selects it (or expands the
/// "Other" fold) the same as tapping its row below.
struct TelegramStorageCategoryChart: View {
    // MARK: Internal

    let entries: [TelegramStorageDisplayEntry]
    let selection: TelegramStorageCategorySelection
    let centerTotal: Int64
    let onSelectCategory: (TelegramNetworkUsageCategory) -> Void
    let onTapGrouped: () -> Void

    var body: some View {
        Chart(entries) { entry in
            SectorMark(
                angle: .value("Size", entry.size),
                innerRadius: .ratio(0.6),
                angularInset: 1.5,
            )
            .cornerRadius(4)
            .foregroundStyle(entry.color)
            .opacity(isIncluded(entry) ? 1 : 0.25)
            .annotation(position: .overlay) {
                if let percentageText = percentageText(for: entry) {
                    Text(percentageText)
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .opacity(isIncluded(entry) ? 1 : 0.25)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityLabel(entry.title)
            .accessibilityValue(formattedBytes(entry.size))
        }
        .chartAngleSelection(value: $selectedSize)
        .chartLegend(.hidden)
        .frame(height: 200)
        .padding(.vertical, 8)
        .overlay {
            VStack(spacing: 2) {
                Text(formattedBytes(centerTotal))
                    .font(.headline)
                    .monospacedDigit()
                Text("Total")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)
        }
        .onChange(of: selectedSize) { _, newValue in
            guard let newValue, let tapped = entry(forCumulativeValue: newValue) else { return }
            selectedSize = nil
            switch tapped {
            case .category(let category, _, _):
                onSelectCategory(category)
            case .grouped:
                onTapGrouped()
            }
        }
    }

    // MARK: Private

    @State private var selectedSize: Int64?

    private var totalSliceSize: Int64 {
        entries.reduce(0) { $0 + $1.size }
    }

    private func isIncluded(_ entry: TelegramStorageDisplayEntry) -> Bool {
        switch entry {
        case .category(let category, _, _):
            selection.isIncluded(category)
        case .grouped(let categories, _, _):
            categories.contains { selection.isIncluded($0) }
        }
    }

    /// Skips the label on slices too thin to legibly hold text of their own.
    private func percentageText(for entry: TelegramStorageDisplayEntry) -> String? {
        guard totalSliceSize > 0 else { return nil }
        let fraction = Double(entry.size) / Double(totalSliceSize)
        guard fraction >= 0.05 else { return nil }
        return "\(Int((fraction * 100).rounded()))%"
    }

    /// `chartAngleSelection` reports the cumulative plot value at the tapped angle, not which mark
    /// was tapped directly - resolved back to an entry by walking the same cumulative order the
    /// chart renders slices in.
    private func entry(forCumulativeValue value: Int64) -> TelegramStorageDisplayEntry? {
        var cumulative: Int64 = 0
        for entry in entries {
            cumulative += entry.size
            if value <= cumulative {
                return entry
            }
        }
        return entries.last
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - TelegramStorageCategoryRow

/// A selectable category row: name, size, and a checkmark when selected - same visual language as
/// the accent-color picker rows in `TelegramAppearanceSettingsView`.
struct TelegramStorageCategoryRow: View {
    // MARK: Internal

    let category: TelegramNetworkUsageCategory
    let size: Int64
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Text(category.title)
                    .foregroundStyle(.primary)
                Spacer()
                Text(formattedBytes(size))
                    .foregroundStyle(.secondary)
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: Private

    private func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - TelegramStorageUsageView

struct TelegramStorageUsageView: View {
    // MARK: Lifecycle

    init(service: any TelegramService, sharedMediaDestination: ((Int64, String) -> AnyView)? = nil) {
        self.service = service
        self.sharedMediaDestination = sharedMediaDestination
    }

    // MARK: Internal

    var body: some View {
        List {
            if let statistics {
                let categoryRows = TelegramStorageUsageStore.categoryRows(
                    byFileType: statistics.byChat.flatMap(\.byFileType),
                )

                Section {
                    if !categoryRows.isEmpty {
                        TelegramStorageCategoryChart(
                            entries: TelegramStorageUsageStore.chartEntries(
                                from: categoryRows,
                                isOtherExpanded: isOtherExpanded,
                            ),
                            selection: selection,
                            centerTotal: selection.totalSize(in: categoryRows),
                            onSelectCategory: { selection.toggle($0) },
                            onTapGrouped: { isOtherExpanded.toggle() },
                        )
                    }
                    LabeledContent("Total", value: formattedBytes(selection.totalSize(in: categoryRows)))
                    LabeledContent("Files", value: "\(statistics.count)")
                    let displayRows = TelegramStorageUsageStore.splitForDisplay(categoryRows)
                    ForEach(displayRows.shown, id: \.category) { entry in
                        TelegramStorageCategoryRow(
                            category: entry.category,
                            size: entry.size,
                            isSelected: selection.isSelected(entry.category),
                            onTap: { selection.toggle(entry.category) },
                        )
                    }
                    if !displayRows.folded.isEmpty {
                        DisclosureGroup(isExpanded: $isOtherExpanded) {
                            ForEach(displayRows.folded, id: \.category) { entry in
                                TelegramStorageCategoryRow(
                                    category: entry.category,
                                    size: entry.size,
                                    isSelected: selection.isSelected(entry.category),
                                    onTap: { selection.toggle(entry.category) },
                                )
                            }
                        } label: {
                            LabeledContent(
                                "Other",
                                value: formattedBytes(displayRows.folded.reduce(0) { $0 + $1.size }),
                            )
                        }
                    }
                } footer: {
                    if categoryRows.contains(where: { $0.category == .avatars }) {
                        Text(
                            "Profile Photos are chat and contact avatars, not attached to any single chat - they don't appear under any chat below.",
                        )
                    }
                }

                if !categoryRows.isEmpty {
                    Section {
                        Button(clearButtonTitle, role: .destructive) {
                            confirmsClear = true
                        }
                        .disabled(isWorking)
                    }
                }

                Section("Chats") {
                    if rows.isEmpty {
                        Text("No cached media yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(rows) { row in
                            NavigationLink {
                                TelegramStorageUsageChatDetailView(
                                    service: service,
                                    row: row,
                                    onCleared: { await load() },
                                    sharedMediaDestination: sharedMediaDestination,
                                )
                            } label: {
                                LabeledContent(row.title, value: formattedBytes(row.stats.size))
                            }
                        }
                    }

                    if hasMoreChats {
                        Button {
                            Task { await loadMore() }
                        } label: {
                            HStack {
                                Spacer()
                                if isLoading {
                                    ProgressView("Loading More Chats…")
                                } else {
                                    Text("Load More")
                                }
                                Spacer()
                            }
                        }
                        .disabled(isLoading)
                    }
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
        .navigationTitle("Storage Usage")
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await load()
        }
        .refreshable { await load() }
        .alert(clearAlertTitle, isPresented: $confirmsClear) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) { Task { await clear() } }
        } message: {
            Text("Cached media will be removed. Files saved with Save As will remain available.")
        }
        .alert("Couldn't Load Storage Usage", isPresented: errorIsPresented) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Private

    /// TDLib folds every chat beyond this count into one anonymous `chatId == 0` "Other Chats"
    /// entry. Starts at one page and grows by the same step via `loadMore()`.
    private static let chatLimitStep = 50

    @State private var chatLimit = Self.chatLimitStep
    @State private var confirmsClear = false
    @State private var errorMessage: String?
    @State private var hasLoaded = false
    @State private var isLoading = false
    @State private var isOtherExpanded = false
    @State private var isWorking = false
    @State private var rows = [TelegramStorageUsageChatRow]()
    @State private var selection = TelegramStorageCategorySelection()
    @State private var statistics: StorageStatistics?

    private let service: any TelegramService
    private let sharedMediaDestination: ((Int64, String) -> AnyView)?

    /// Whether there's a real chat beyond `chatLimit` still waiting to be revealed. Profile
    /// Photos always land in the `chatId == 0` bucket regardless of `chatLimit` (see
    /// `TelegramStorageUsageStore.resolveRows`), so they're excluded here - otherwise "Load More"
    /// would never go away for an account with any avatar cache at all, even once every real chat
    /// is already shown individually.
    private var hasMoreChats: Bool {
        guard let otherChat = statistics?.byChat.first(where: { $0.chatId == 0 }) else { return false }
        let residualCategories = TelegramStorageUsageStore.categoryRows(byFileType: otherChat.byFileType)
            .filter { $0.category != .avatars }
        return residualCategories.contains { $0.size > 0 }
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

    private var clearButtonTitle: String {
        selection.categories.isEmpty ? "Clear All" : "Clear Selected"
    }

    private var clearAlertTitle: String {
        selection.categories.isEmpty ? "Clear All Cached Media?" : "Clear Selected Media?"
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    @MainActor private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let statistics = try await service.getStorageStatistics(chatLimit: chatLimit)
            self.statistics = statistics
            rows = await TelegramStorageUsageStore.resolveRows(byChat: statistics.byChat, service: service)
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }

    @MainActor private func loadMore() async {
        chatLimit += Self.chatLimitStep
        await load()
    }

    @MainActor private func clear() async {
        guard let statistics else { return }
        let categoryRows = TelegramStorageUsageStore.categoryRows(byFileType: statistics.byChat.flatMap(\.byFileType))
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await service.optimizeStorage(
                chatIds: [],
                chatLimit: 0,
                count: Int(Int32.max),
                excludeChatIds: [],
                fileTypes: selection.fileTypes(in: categoryRows),
                immunityDelay: 0,
                returnDeletedFileStatistics: false,
                size: Int64.max,
                ttl: 0,
            )
            selection = TelegramStorageCategorySelection()
            await load()
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }
}

// MARK: - TelegramStorageUsageChatDetailView

struct TelegramStorageUsageChatDetailView: View {
    // MARK: Internal

    let service: any TelegramService
    let row: TelegramStorageUsageChatRow
    /// Awaited by the caller to refresh its own list once this chat's cache is cleared.
    let onCleared: () async -> Void
    /// Injected by the app target so this cross-platform screen can present the shared-media
    /// browser without `BetterTGShared` depending on a platform app's own view types - `nil` hides
    /// the row entirely (currently supplied on iOS only).
    var sharedMediaDestination: ((Int64, String) -> AnyView)?

    var body: some View {
        List {
            Section {
                if !categoryRows.isEmpty {
                    TelegramStorageCategoryChart(
                        entries: TelegramStorageUsageStore.chartEntries(
                            from: categoryRows,
                            isOtherExpanded: isOtherExpanded,
                        ),
                        selection: selection,
                        centerTotal: selection.totalSize(in: categoryRows),
                        onSelectCategory: { selection.toggle($0) },
                        onTapGrouped: { isOtherExpanded.toggle() },
                    )
                }
                let displayRows = TelegramStorageUsageStore.splitForDisplay(categoryRows)
                ForEach(displayRows.shown, id: \.category) { entry in
                    TelegramStorageCategoryRow(
                        category: entry.category,
                        size: entry.size,
                        isSelected: selection.isSelected(entry.category),
                        onTap: { selection.toggle(entry.category) },
                    )
                }
                if !displayRows.folded.isEmpty {
                    DisclosureGroup(isExpanded: $isOtherExpanded) {
                        ForEach(displayRows.folded, id: \.category) { entry in
                            TelegramStorageCategoryRow(
                                category: entry.category,
                                size: entry.size,
                                isSelected: selection.isSelected(entry.category),
                                onTap: { selection.toggle(entry.category) },
                            )
                        }
                    } label: {
                        LabeledContent("Other", value: formattedBytes(displayRows.folded.reduce(0) { $0 + $1.size }))
                    }
                }

                if sharedMediaDestination != nil {
                    Button {
                        showsSharedMedia = true
                    } label: {
                        Label("View Shared Media", systemImage: "photo.on.rectangle")
                    }
                }
            }

            Section {
                Button(clearButtonTitle, role: .destructive) {
                    confirmsClear = true
                }
                .disabled(isWorking)
            }
        }
        .navigationTitle(row.title)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .sheet(isPresented: $showsSharedMedia) {
                sharedMediaDestination?(row.chatId, row.title)
            }
            .alert(clearAlertTitle, isPresented: $confirmsClear) {
                Button("Cancel", role: .cancel) {}
                Button("Clear", role: .destructive) { Task { await clear() } }
            } message: {
                Text("Cached media for this chat will be removed. Files saved with Save As will remain available.")
            }
            .alert("Couldn't Clear Chat Cache", isPresented: errorIsPresented) {
                Button("OK") {}
            } message: {
                Text(errorMessage ?? "")
            }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var confirmsClear = false
    @State private var errorMessage: String?
    @State private var isOtherExpanded = false
    @State private var isWorking = false
    @State private var selection = TelegramStorageCategorySelection()
    @State private var showsSharedMedia = false

    private var categoryRows: [(category: TelegramNetworkUsageCategory, size: Int64, count: Int)] {
        TelegramStorageUsageStore.categoryRows(byFileType: row.stats.byFileType)
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

    private var clearButtonTitle: String {
        selection.categories.isEmpty ? "Clear Media in This Chat" : "Clear Selected"
    }

    private var clearAlertTitle: String {
        selection.categories.isEmpty ? "Clear Media in \(row.title)?" : "Clear Selected Media?"
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    @MainActor private func clear() async {
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await service.optimizeStorage(
                chatIds: [row.chatId],
                chatLimit: 0,
                count: Int(Int32.max),
                excludeChatIds: [],
                fileTypes: selection.fileTypes(in: categoryRows),
                immunityDelay: 0,
                returnDeletedFileStatistics: false,
                size: Int64.max,
                ttl: 0,
            )
            await onCleared()
            dismiss()
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }
}
