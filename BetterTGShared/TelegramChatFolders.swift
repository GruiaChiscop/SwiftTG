// TelegramChatFolders.swift

import SwiftUI
@preconcurrency import TDLibKit

// MARK: - TelegramChatFolderIconOption

/// Mirrors the fixed icon-name set `ChatFolderIcon.name` documents (`"All"`, `"Unread"`, ...,
/// `"Palette"`) - TDLib only accepts one of these exact strings, there's no free-form icon upload.
enum TelegramChatFolderIconOption: String, CaseIterable, Identifiable {
    case all = "All"
    case unread = "Unread"
    case unmuted = "Unmuted"
    case bots = "Bots"
    case channels = "Channels"
    case groups = "Groups"
    case privateChats = "Private"
    case custom = "Custom"
    case setup = "Setup"
    case cat = "Cat"
    case crown = "Crown"
    case favorite = "Favorite"
    case flower = "Flower"
    case game = "Game"
    case home = "Home"
    case love = "Love"
    case mask = "Mask"
    case party = "Party"
    case sport = "Sport"
    case study = "Study"
    case trade = "Trade"
    case travel = "Travel"
    case work = "Work"
    case airplane = "Airplane"
    case book = "Book"
    case light = "Light"
    case like = "Like"
    case money = "Money"
    case note = "Note"
    case palette = "Palette"

    // MARK: Lifecycle

    init(_ icon: ChatFolderIcon) {
        self = Self(rawValue: icon.name) ?? .custom
    }

    // MARK: Internal

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .all: "tray.full"
        case .unread: "envelope.badge"
        case .unmuted: "bell"
        case .bots: "cpu"
        case .channels: "megaphone"
        case .groups: "person.2"
        case .privateChats: "person"
        case .custom: "folder"
        case .setup: "gearshape"
        case .cat: "cat"
        case .crown: "crown"
        case .favorite: "star"
        case .flower: "leaf"
        case .game: "gamecontroller"
        case .home: "house"
        case .love: "heart"
        case .mask: "theatermasks"
        case .party: "party.popper"
        case .sport: "sportscourt"
        case .study: "book"
        case .trade: "chart.line.uptrend.xyaxis"
        case .travel: "suitcase"
        case .work: "briefcase"
        case .airplane: "airplane"
        case .book: "book.closed"
        case .light: "lightbulb"
        case .like: "hand.thumbsup"
        case .money: "banknote"
        case .note: "note.text"
        case .palette: "paintpalette"
        }
    }

    var chatFolderIcon: ChatFolderIcon {
        ChatFolderIcon(name: rawValue)
    }
}

// MARK: - TelegramChatFoldersView

/// Top-level Settings entry, matching official Telegram: `Settings_ChatFolders` is its own
/// root-level screen there (not nested under another settings page), so this is wired directly
/// into `YouView`/`MacSettingsView` the same way.
struct TelegramChatFoldersView: View {
    // MARK: Lifecycle

    init(service: any TelegramService) {
        self.service = service
    }

    // MARK: Internal

    var body: some View {
        List {
            if !folders.isEmpty {
                Section {
                    ForEach(folders) { folder in
                        folderRow(folder)
                    }
                    .onMove(perform: moveFolders)
                } footer: {
                    Text("Folders appear as tabs above your chat list. Drag to reorder.")
                }
            }

            Section {
                #if os(iOS)
                    NavigationLink {
                        TelegramChatFolderEditView(service: service, existingId: nil) {}
                    } label: {
                        Label("Create New Folder", systemImage: "plus")
                    }
                #else
                    Button {
                        editingFolderId = .new
                    } label: {
                        Label("Create New Folder", systemImage: "plus")
                    }
                    .buttonStyle(.plain)
                #endif
            }

            if !recommendedFolders.isEmpty {
                Section {
                    ForEach(Array(recommendedFolders.enumerated()), id: \.offset) { _, recommended in
                        recommendedFolderRow(recommended)
                    }
                } header: {
                    Text("Recommended Folders")
                }
            }
        }
        .navigationTitle("Chat Folders")
        #if os(iOS)
            .toolbar {
                if !folders.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        EditButton()
                    }
                }
            }
        #endif
            .task {
                    guard !hasLoaded else { return }
                    hasLoaded = true
                    await loadRecommended()
                }
                .onReceive(service.chatFoldersPublisher) { update in
                    guard let update else { return }
                    folders = update.chatFolders
                }
        #if os(macOS)
        .sheet(item: $editingFolderId) { target in
            NavigationStack {
                TelegramChatFolderEditView(service: service, existingId: target.id) {}
            }
            .frame(minWidth: 420, minHeight: 480)
        }
        #endif
        .alert("Chat Folders operation failed", isPresented: errorIsPresented) {
                Button("OK") {}
            } message: {
                Text(errorMessage ?? "")
            }
    }

    // MARK: Private

    /// Wraps an existing folder id, or `nil` for "create a new one" - `Identifiable` so it works
    /// with `.sheet(item:)` on macOS, where `nil` and "editing folder 0" must be distinguishable.
    private struct EditTarget: Identifiable {
        static let new = EditTarget(id: nil)

        let id: Int?
    }

    @State private var errorMessage: String?
    #if os(macOS)
    @State private var editingFolderId: EditTarget?
    #endif
    @State private var folders = [ChatFolderInfo]()
    @State private var hasLoaded = false
    @State private var recommendedFolders = [RecommendedChatFolder]()

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

    private func folderRow(_ folder: ChatFolderInfo) -> some View {
        #if os(iOS)
            NavigationLink {
                TelegramChatFolderEditView(service: service, existingId: folder.id) {}
            } label: {
                folderLabel(folder)
            }
        #else
            Button {
                editingFolderId = EditTarget(id: folder.id)
            } label: {
                folderLabel(folder)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        #endif
    }

    private func folderLabel(_ folder: ChatFolderInfo) -> some View {
        Label {
            Text(folder.name.text.text)
        } icon: {
            Image(systemName: TelegramChatFolderIconOption(folder.icon).symbolName)
        }
    }

    private func recommendedFolderRow(_ recommended: RecommendedChatFolder) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(recommended.folder.name.text.text)
                    .font(.body)
                Text(recommended.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Add") {
                Task { await addRecommended(recommended) }
            }
            .buttonStyle(.borderless)
        }
    }

    private func moveFolders(from source: IndexSet, to destination: Int) {
        var reordered = folders
        reordered.move(fromOffsets: source, toOffset: destination)
        folders = reordered
        Task {
            do {
                _ = try await service.reorderChatFolders(
                    chatFolderIds: reordered.map(\.id),
                    mainChatListPosition: 0,
                )
            } catch {
                errorMessage = telegramErrorDescription(error)
            }
        }
    }

    @MainActor private func loadRecommended() async {
        guard let result = try? await service.getRecommendedChatFolders() else { return }
        recommendedFolders = result.chatFolders
    }

    @MainActor private func addRecommended(_ recommended: RecommendedChatFolder) async {
        do {
            _ = try await service.createChatFolder(folder: recommended.folder)
            recommendedFolders.removeAll { $0.folder == recommended.folder }
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }
}

// MARK: - TelegramChatFolderEditView

/// Shared by both "create" (`existingId == nil`) and "edit" (`existingId != nil`) - the two flows
/// differ only in what loads at launch and whether a Delete section is shown.
struct TelegramChatFolderEditView: View {
    // MARK: Lifecycle

    init(service: any TelegramService, existingId: Int?, onSaved: @escaping () -> Void) {
        self.service = service
        self.existingId = existingId
        self.onSaved = onSaved
    }

    // MARK: Internal

    let existingId: Int?
    let onSaved: () -> Void

    var body: some View {
        Form {
            Section("Name") {
                TextField("Folder Name", text: $name)
            }

            Section("Icon") {
                LazyVGrid(columns: iconGridColumns, spacing: 12) {
                    ForEach(TelegramChatFolderIconOption.allCases) { option in
                        Button {
                            icon = option
                        } label: {
                            Image(systemName: option.symbolName)
                                .font(.title3)
                                .frame(width: 36, height: 36)
                                .background(icon == option ? Color.accentColor.opacity(0.2) : .clear, in: Circle())
                                .foregroundStyle(icon == option ? Color.accentColor : .primary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(option.rawValue)
                        .accessibilityAddTraits(icon == option ? [.isSelected] : [])
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                Toggle("Contacts", isOn: $includeContacts)
                Toggle("Other Private Chats", isOn: $includeNonContacts)
                Toggle("Groups", isOn: $includeGroups)
                Toggle("Channels", isOn: $includeChannels)
                Toggle("Bots", isOn: $includeBots)
            } header: {
                Text("Include Chat Types")
            }

            chatListSection(
                title: "Included Chats",
                chatIds: $includedChatIds,
                pickerTarget: .included,
            )

            Section {
                Toggle("Exclude Muted Chats", isOn: $excludeMuted)
                Toggle("Exclude Read Chats", isOn: $excludeRead)
                Toggle("Exclude Archived Chats", isOn: $excludeArchived)
            } header: {
                Text("Exclude")
            }

            chatListSection(
                title: "Excluded Chats",
                chatIds: $excludedChatIds,
                pickerTarget: .excluded,
            )

            chatListSection(
                title: "Pinned in Folder",
                chatIds: $pinnedChatIds,
                pickerTarget: .pinned,
            )

            if existingId != nil {
                Section {
                    Button("Delete Folder", role: .destructive) {
                        Task { await beginDelete() }
                    }
                    .disabled(isPreparingDelete)
                }
            }
        }
        .navigationTitle(existingId == nil ? "New Folder" : "Edit Folder")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .toolbar {
                #if os(macOS)
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                #endif
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") {
                            Task { await save() }
                        }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .task {
                guard !hasLoaded else { return }
                hasLoaded = true
                await load()
            }
            .sheet(item: $pickerTarget) { target in
                TelegramChatFolderChatPickerView(
                    service: service,
                    preselectedChatIds: Set(chatIds(for: target)),
                ) { selectedIds in
                    setChatIds(selectedIds, for: target)
                }
            }
            .alert(
                "Delete this folder?",
                isPresented: $confirmsDelete,
                presenting: existingId,
            ) { folderId in
                if chatsToLeaveCandidates.isEmpty {
                    Button("Delete", role: .destructive) {
                        Task { await delete(folderId, leaveChatIds: []) }
                    }
                } else {
                    Button("Delete and Leave Chats", role: .destructive) {
                        Task { await delete(folderId, leaveChatIds: chatsToLeaveCandidates) }
                    }
                    Button("Delete Folder Only", role: .destructive) {
                        Task { await delete(folderId, leaveChatIds: []) }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text(
                    chatsToLeaveCandidates.isEmpty
                        ? "Chats inside the folder aren't affected - only the folder itself is removed."
                        : "\(chatsToLeaveCandidates.count) chat(s) in this folder aren't in any other folder. "
                            + "You can leave them too, or keep them and only remove the folder.",
                )
            }
            .alert("Chat Folders operation failed", isPresented: errorIsPresented) {
                Button("OK") {}
            } message: {
                Text(errorMessage ?? "")
            }
    }

    // MARK: Private

    private enum ChatListTarget: Identifiable {
        case included
        case excluded
        case pinned

        // MARK: Internal

        var id: Self { self }

        var title: String {
            switch self {
            case .included: "Included Chats"
            case .excluded: "Excluded Chats"
            case .pinned: "Pinned in Folder"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss

    @State private var chatTitles = [Int64: String]()
    @State private var chatsToLeaveCandidates = [Int64]()
    @State private var confirmsDelete = false
    @State private var errorMessage: String?
    @State private var excludeArchived = false
    @State private var excludeMuted = false
    @State private var excludeRead = false
    @State private var excludedChatIds = [Int64]()
    @State private var hasLoaded = false
    @State private var icon = TelegramChatFolderIconOption.custom
    @State private var includeBots = false
    @State private var includeChannels = false
    @State private var includeContacts = false
    @State private var includeGroups = false
    @State private var includeNonContacts = false
    @State private var includedChatIds = [Int64]()
    @State private var isPreparingDelete = false
    @State private var isSaving = false
    @State private var name = ""
    @State private var pickerTarget: ChatListTarget?
    @State private var pinnedChatIds = [Int64]()

    private let service: any TelegramService

    private let iconGridColumns = Array(repeating: GridItem(.flexible()), count: 6)

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

    private var draftFolder: ChatFolder {
        ChatFolder(
            colorId: -1,
            excludeArchived: excludeArchived,
            excludeMuted: excludeMuted,
            excludeRead: excludeRead,
            excludedChatIds: excludedChatIds,
            icon: icon.chatFolderIcon,
            includeBots: includeBots,
            includeChannels: includeChannels,
            includeContacts: includeContacts,
            includeGroups: includeGroups,
            includeNonContacts: includeNonContacts,
            includedChatIds: includedChatIds,
            isShareable: false,
            name: ChatFolderName(
                animateCustomEmoji: false,
                text: FormattedText(entities: [], text: name.trimmingCharacters(in: .whitespacesAndNewlines)),
            ),
            pinnedChatIds: pinnedChatIds,
        )
    }

    private func chatListSection(title: String, chatIds: Binding<[Int64]>, pickerTarget target: ChatListTarget)
        -> some View
    {
        Section {
            ForEach(chatIds.wrappedValue, id: \.self) { chatId in
                Text(chatTitles[chatId] ?? "…")
            }
            .onDelete { offsets in
                chatIds.wrappedValue.remove(atOffsets: offsets)
            }

            Button {
                pickerTarget = target
            } label: {
                Label("Add Chats…", systemImage: "plus")
            }
        } header: {
            Text(title)
        }
    }

    private func chatIds(for target: ChatListTarget) -> [Int64] {
        switch target {
        case .included: includedChatIds
        case .excluded: excludedChatIds
        case .pinned: pinnedChatIds
        }
    }

    private func setChatIds(_ ids: Set<Int64>, for target: ChatListTarget) {
        let ordered = Array(ids)
        switch target {
        case .included: includedChatIds = ordered
        case .excluded: excludedChatIds = ordered
        case .pinned: pinnedChatIds = ordered
        }
        Task { await resolveTitles(for: ordered) }
    }

    @MainActor private func load() async {
        guard let existingId else {
            if let suggested = try? await service.getChatFolderDefaultIconName(folder: draftFolder) {
                icon = TelegramChatFolderIconOption(suggested)
            }
            return
        }
        do {
            let folder = try await service.getChatFolder(chatFolderId: existingId)
            apply(folder)
            await resolveTitles(for: folder.includedChatIds + folder.excludedChatIds + folder.pinnedChatIds)
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }

    @MainActor private func apply(_ folder: ChatFolder) {
        name = folder.name.text.text
        icon = TelegramChatFolderIconOption(folder.icon ?? ChatFolderIcon(name: "Custom"))
        excludeArchived = folder.excludeArchived
        excludeMuted = folder.excludeMuted
        excludeRead = folder.excludeRead
        excludedChatIds = folder.excludedChatIds
        includeBots = folder.includeBots
        includeChannels = folder.includeChannels
        includeContacts = folder.includeContacts
        includeGroups = folder.includeGroups
        includeNonContacts = folder.includeNonContacts
        includedChatIds = folder.includedChatIds
        pinnedChatIds = folder.pinnedChatIds
    }

    @MainActor private func resolveTitles(for chatIds: [Int64]) async {
        let missingIds = chatIds.filter { chatTitles[$0] == nil }
        guard !missingIds.isEmpty else { return }
        let resolved = await missingIds.concurrentCompactMap { chatId -> (Int64, String)? in
            guard let chat = try? await service.getChat(chatId: chatId) else { return nil }
            return (chatId, chat.title)
        }
        for (chatId, title) in resolved {
            chatTitles[chatId] = title
        }
    }

    @MainActor private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            _ =
                if let existingId {
                    try await service.editChatFolder(chatFolderId: existingId, folder: draftFolder)
                } else {
                    try await service.createChatFolder(folder: draftFolder)
                }
            onSaved()
            dismiss()
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }

    @MainActor private func beginDelete() async {
        isPreparingDelete = true
        defer { isPreparingDelete = false }
        guard let existingId else { return }
        chatsToLeaveCandidates = await (try? service.getChatFolderChatsToLeave(chatFolderId: existingId).chatIds) ?? []
        confirmsDelete = true
    }

    @MainActor private func delete(_ folderId: Int, leaveChatIds: [Int64]) async {
        do {
            _ = try await service.deleteChatFolder(chatFolderId: folderId, leaveChatIds: leaveChatIds)
            onSaved()
            dismiss()
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }
}

// MARK: - TelegramChatFolderChatPickerView

/// Cross-platform search + multi-select chat picker for a folder's included/excluded/pinned chat
/// lists. Deliberately its own lightweight fetch via `searchChats`/`getChats` rather than reusing
/// `RootVM.allChats` (iOS-only) or `CustomChat` (also iOS-only) - this lives in `BetterTGShared`
/// and needs to work unmodified on macOS too.
struct TelegramChatFolderChatPickerView: View {
    // MARK: Lifecycle

    init(service: any TelegramService, preselectedChatIds: Set<Int64>, onDone: @escaping (Set<Int64>) -> Void) {
        self.service = service
        _selectedChatIds = State(initialValue: preselectedChatIds)
        self.onDone = onDone
    }

    // MARK: Internal

    let onDone: (Set<Int64>) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(displayedChats, id: \.id) { chat in
                    Button {
                        toggle(chat.id)
                    } label: {
                        HStack {
                            Text(chat.title.isEmpty ? "Untitled Chat" : chat.title)
                                .foregroundStyle(.primary)
                            Spacer()
                            if selectedChatIds.contains(chat.id) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.tint)
                            } else {
                                Image(systemName: "circle")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .overlay {
                if isLoading, displayedChats.isEmpty {
                    ProgressView()
                }
            }
            .navigationTitle("Choose Chats")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .searchable(text: $query, prompt: "Search chats")
                .task {
                    guard !hasLoaded else { return }
                    hasLoaded = true
                    await loadInitialChats()
                }
                .task(id: normalizedQuery) {
                    await search()
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            onDone(selectedChatIds)
                            dismiss()
                        }
                    }
                }
        }
        .frame(minWidth: 380, minHeight: 480)
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    @State private var browsedChats = [Chat]()
    @State private var hasLoaded = false
    @State private var isLoading = false
    @State private var query = ""
    @State private var searchResults = [Chat]()
    @State private var selectedChatIds: Set<Int64>

    private let service: any TelegramService

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var displayedChats: [Chat] {
        normalizedQuery.isEmpty ? browsedChats : searchResults
    }

    private func toggle(_ chatId: Int64) {
        if !selectedChatIds.insert(chatId).inserted {
            selectedChatIds.remove(chatId)
        }
    }

    @MainActor private func loadInitialChats() async {
        isLoading = true
        defer { isLoading = false }
        _ = try? await service.loadChats(chatList: .chatListMain, limit: 200)
        guard let result = try? await service.getChats(chatList: .chatListMain, limit: 200) else { return }
        browsedChats = await result.chatIds.concurrentCompactMap { try? await service.getChat(chatId: $0) }
    }

    @MainActor private func search() async {
        guard !normalizedQuery.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        guard let result = try? await service.searchChats(limit: 50, query: normalizedQuery, typeFilter: nil) else {
            return
        }
        searchResults = await result.chatIds.concurrentCompactMap { try? await service.getChat(chatId: $0) }
    }
}
