// FolderView.swift

import SwiftUI

struct FolderView: View {
    // MARK: Internal

    @State var folder: CustomFolder

    @State var rootVM = RootVM.shared
    @State var chatToMute: CustomChat?
    @State var isEditing = false
    @State var selectedChatIds = Set<Int64>()
    @State var confirmsBulkDelete = false

    var chats: [CustomChat] {
        folder.chats
            .sorted { $0.position.order > $1.position.order }
    }

    var isSearching: Bool {
        !rootVM.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasArchive: Bool {
        !(rootVM.archive?.chats.isEmpty ?? true)
    }

    var selectedChats: [CustomChat] {
        chats.filter { selectedChatIds.contains($0.id) }
    }

    var allSelectedAreRead: Bool {
        !selectedChats.isEmpty && selectedChats.allSatisfy { !$0.hasUnreadMessages && !$0.isMarkedAsUnread }
    }

    var allSelectedAreMuted: Bool {
        !selectedChats.isEmpty && selectedChats.allSatisfy(\.isMuted)
    }

    var hasUnreadChats: Bool {
        chats.contains { $0.hasUnreadMessages || $0.isMarkedAsUnread }
    }

    var body: some View {
        ScrollViewReader { scrollViewProxy in
            bodyView.onAppear { folder.scrollViewProxy = scrollViewProxy }
        }
        .onChange(of: rootVM.query) { _, query in
            rootVM.search(query, in: folder.chatList)
        }
        .onAppear {
            guard !rootVM.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            rootVM.search(rootVM.query, in: folder.chatList)
        }
        .toolbar {
            if !chats.isEmpty, !isSearching {
                ToolbarItem(placement: .topBarLeading) {
                    // A custom toggle rather than the system `EditButton()` - this view mixes
                    // `NavigationLink`-per-row navigation with a from-scratch multi-select bar
                    // (bulk Read/Mute/Archive/Delete), which `EditButton()`'s own `EditMode`
                    // plumbing doesn't drive on its own; styled to match it instead.
                    Button(isEditing ? "Done" : "Edit") {
                        withAnimation {
                            isEditing.toggle()
                            if !isEditing {
                                selectedChatIds.removeAll()
                            }
                        }
                    }
                }
                if isEditing {
                    ToolbarItem(placement: .topBarTrailing) {
                        // Independent of `selectedChatIds` - reads every unread chat in this
                        // folder, selected or not, matching what "Read All" implies.
                        Button("Read All") {
                            performReadAll()
                        }
                        .disabled(!hasUnreadChats)
                    }
                }
            }
        }
    }
    
    var bodyView: some View {
        List {
            Color.clear
                .frame(height: 0)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .accessibilityHidden(true)
                .id("top")

            if isSearching {
                searchResults
            } else if chats.isEmpty, !hasArchive {
                Text("Empty folder")
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                if folder.type == .main, let archive = rootVM.archive, hasArchive {
                    archivedRow(archive)
                }

                ForEach(chats) { customChat in
                    Group {
                        if isEditing {
                            Button {
                                toggleSelection(customChat)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(
                                        systemName: selectedChatIds.contains(customChat.id)
                                            ? "checkmark.circle.fill"
                                            : "circle",
                                    )
                                    .font(.title3)
                                    .foregroundStyle(
                                        selectedChatIds.contains(customChat.id) ? Color.accentColor : .secondary,
                                    )
                                    .accessibilityHidden(true)

                                    ChatsListItemView(customChat: customChat)
                                }
                            }
                            .accessibilityAddTraits(selectedChatIds.contains(customChat.id) ? [.isSelected] : [])
                        } else {
                            NavigationLink(value: Route.customChat(customChat, messageId: nil)) {
                                ChatsListItemView(customChat: customChat)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityActions {
                        // SwiftUI presents .accessibilityActions in reverse declaration order, so
                        // these are declared back-to-front to have VoiceOver announce them
                        // Mark as Read -> Archive -> Pin -> Mute -> Clear History -> Leave/Delete.
                        let policy = customChat.actionPolicy
                        if let leaveTitle = policy.leaveActionTitle {
                            Button(leaveTitle) {
                                requestLeave(customChat)
                            }
                        } else if policy.canDeleteChat {
                            Button(policy.deleteActionTitle) {
                                requestDelete(customChat)
                            }
                        }
                        if policy.canClearHistory {
                            Button("Clear History") {
                                requestClearHistory(customChat)
                            }
                        }
                        Button(customChat.isMuted ? "Unmute" : "Mute") {
                            toggleMuted(customChat)
                        }
                        Button(customChat.position.isPinned ? "Unpin" : "Pin") {
                            rootVM.togglePinned(for: customChat, in: folder.chatList)
                        }
                        Button(folder.type == .archive ? "Unarchive" : "Archive") {
                            toggleArchived(customChat)
                        }
                        Button(customChat.hasUnreadMessages ? "Mark as Read" : "Mark as Unread") {
                            rootVM.toggleRead(for: customChat)
                        }
                    }
                    .contextMenu {
                        contextMenu(for: customChat)
                    } preview: {
                        LazyView {
                            NavigationStack {
                                ChatView(customChat: customChat)
                                    .environment(\.isPreview, true)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }

            Color.clear
                .frame(height: 0)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .accessibilityHidden(true)
                .id("bottom")
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .listRowSpacing(8)
        .background(Color(uiColor: .systemGroupedBackground))
        .scrollIndicators(.visible)
        .safeAreaInset(edge: .bottom) {
            if isEditing {
                editingActionBar
            }
        }
        .confirmationDialog(
            "Delete \(selectedChatIds.count) chat\(selectedChatIds.count == 1 ? "" : "s")?",
            isPresented: $confirmsBulkDelete,
        ) {
            Button("Delete", role: .destructive) { performBulkDelete() }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Mute \(chatToMute?.displayTitle ?? "chat")",
            isPresented: Binding(
                get: { chatToMute != nil },
                set: {
                    if !$0 {
                        chatToMute = nil
                    }
                },
            ),
        ) {
            ForEach(TelegramMutePreset.allCases) { preset in
                Button(preset.title) { muteSelectedChat(for: preset.duration) }
            }
            Button("Cancel", role: .cancel) { chatToMute = nil }
        }
    }

    var editingActionBar: some View {
        HStack(spacing: 0) {
            editingActionButton(
                title: allSelectedAreRead ? "Unread" : "Read",
                systemImage: allSelectedAreRead ? "envelope.badge" : "envelope.open",
                action: performBulkRead,
            )
            Spacer()
            editingActionButton(
                title: allSelectedAreMuted ? "Unmute" : "Mute",
                systemImage: allSelectedAreMuted ? "speaker.wave.2" : "speaker.slash",
                action: performBulkMute,
            )
            Spacer()
            editingActionButton(
                title: folder.type == .archive ? "Unarchive" : "Archive",
                systemImage: folder.type == .archive ? "tray.and.arrow.up" : "archivebox",
                action: performBulkArchive,
            )
            Spacer()
            editingActionButton(title: "Delete", systemImage: "trash", role: .destructive) {
                confirmsBulkDelete = true
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .disabled(selectedChatIds.isEmpty)
        .background(.bar)
    }

    /// Inline row for the archive, shown at the top of the "All Chats" folder only when there's at
    /// least one archived chat - matches how other Telegram-family clients surface it (a row that
    /// only exists when relevant), rather than a permanent toolbar button.
    func archivedRow(_ archive: CustomFolder) -> some View {
        Button {
            rootVM.navigate(to: .archive(archive))
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.gray.opacity(0.3))
                    Image(systemName: "archivebox.fill")
                        .foregroundStyle(.secondary)
                }
                .frame(width: 54, height: 54)

                Text("Archived")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                Text("\(archive.chats.count)")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .accessibilityLabel("Archived, \(archive.chats.count) chat\(archive.chats.count == 1 ? "" : "s")")
    }

    func editingActionButton(
        title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void,
    ) -> some View {
        Button(role: role, action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.title3)
                Text(title)
                    .font(.caption2)
            }
        }
    }

    @ViewBuilder func contextMenu(for customChat: CustomChat) -> some View {
        let policy = customChat.actionPolicy
        let isPinned = customChat.position.isPinned
        let hasUnreadMessages = customChat.hasUnreadMessages
        Button(
            hasUnreadMessages ? "Mark as Read" : "Mark as Unread",
            systemImage: hasUnreadMessages
                ? "envelope.open"
                : "envelope.badge",
        ) {
            rootVM.toggleRead(for: customChat)
        }

        Button(
            folder.type == .archive ? "Unarchive" : "Archive",
            systemImage: folder.type == .archive ? "tray.and.arrow.up" : "archivebox",
        ) {
            toggleArchived(customChat)
        }

        Button(isPinned ? "Unpin" : "Pin", systemImage: isPinned ? "pin.slash.fill" : "pin.fill") {
            rootVM.togglePinned(for: customChat, in: folder.chatList)
        }

        Button(
            customChat.isMuted ? "Unmute" : "Mute",
            systemImage: customChat.isMuted ? "speaker.wave.2" : "speaker.slash",
        ) {
            toggleMuted(customChat)
        }

        if policy.canClearHistory {
            Button("Clear History", systemImage: "eraser", role: .destructive) {
                requestClearHistory(customChat)
            }
        }

        if let leaveTitle = policy.leaveActionTitle {
            Button(
                leaveTitle,
                systemImage: "rectangle.portrait.and.arrow.right",
                role: .destructive,
            ) {
                requestLeave(customChat)
            }
        } else if policy.canDeleteChat {
            Button(policy.deleteActionTitle, systemImage: "trash", role: .destructive) {
                requestDelete(customChat)
            }
        }
    }

    // MARK: Private

    @ViewBuilder private var searchResults: some View {
        if !rootVM.searchChatResults.isEmpty {
            Section {
                ForEach(rootVM.searchChatResults) { customChat in
                    NavigationLink(value: Route.customChat(customChat, messageId: nil)) {
                        ChatsListItemView(customChat: customChat)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Chats (\(rootVM.searchChatResults.count))")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
            }
        }

        if !rootVM.searchGlobalChatResults.isEmpty {
            Section {
                ForEach(rootVM.searchGlobalChatResults) { customChat in
                    NavigationLink(value: Route.customChat(customChat, messageId: nil)) {
                        ChatsListItemView(customChat: customChat)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Global Search")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
            }
        }

        if !rootVM.searchMessageResults.isEmpty {
            Section {
                ForEach(Array(rootVM.searchMessageResults.enumerated()), id: \.offset) { _, message in
                    if let customChat = rootVM.searchResultChatsById[message.chatId] {
                        NavigationLink(value: Route.customChat(customChat, messageId: message.id)) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(rootVM.searchMessageChatTitles[message.chatId] ?? customChat.displayTitle)
                                        .fontWeight(.semibold)
                                    Spacer()
                                    Text(
                                        Date(timeIntervalSince1970: TimeInterval(message.date)),
                                        format: .dateTime.day().month().hour().minute(),
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                Text(telegramMessageContentDescription(message))
                                    .lineLimit(2)
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                Text("Messages (\(rootVM.searchMessageResults.count))")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
            }
        }

        if rootVM.isSearching {
            HStack {
                Spacer()
                ProgressView("Searching…")
                Spacer()
            }
            .padding()
        } else if rootVM.searchChatResults.isEmpty, rootVM.searchGlobalChatResults.isEmpty,
                  rootVM.searchMessageResults.isEmpty
        {
            ContentUnavailableView.search(text: rootVM.query)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }

    private func requestDelete(_ customChat: CustomChat) {
        rootVM.requestDelete(customChat)
    }

    private func requestClearHistory(_ customChat: CustomChat) {
        rootVM.requestClearHistory(customChat)
    }

    private func requestLeave(_ customChat: CustomChat) {
        rootVM.requestLeave(customChat)
    }

    private func toggleArchived(_ customChat: CustomChat) {
        rootVM.toggleArchived(customChat, isCurrentlyArchived: folder.type == .archive)
    }

    private func toggleMuted(_ customChat: CustomChat) {
        if customChat.isMuted {
            setMuteDuration(0, for: customChat)
        } else {
            chatToMute = customChat
        }
    }

    private func muteSelectedChat(for duration: Int) {
        guard let chatToMute else { return }
        self.chatToMute = nil
        setMuteDuration(duration, for: chatToMute)
    }

    private func setMuteDuration(_ duration: Int, for customChat: CustomChat) {
        rootVM.setMuteDuration(duration, for: customChat)
    }

    private func toggleSelection(_ customChat: CustomChat) {
        if !selectedChatIds.insert(customChat.id).inserted {
            selectedChatIds.remove(customChat.id)
        }
    }

    private func performBulkRead() {
        let targetIsUnread = !allSelectedAreRead
        for chat in selectedChats {
            let chatIsUnread = chat.hasUnreadMessages || chat.isMarkedAsUnread
            if chatIsUnread == targetIsUnread {
                rootVM.toggleRead(for: chat)
            }
        }
        endEditing()
    }

    private func performReadAll() {
        for chat in chats where chat.hasUnreadMessages || chat.isMarkedAsUnread {
            rootVM.toggleRead(for: chat)
        }
        endEditing()
    }

    private func performBulkMute() {
        let duration = allSelectedAreMuted ? 0 : Int(Int32.max)
        for chat in selectedChats {
            rootVM.setMuteDuration(duration, for: chat)
        }
        endEditing()
    }

    private func performBulkArchive() {
        let isCurrentlyArchived = folder.type == .archive
        for chat in selectedChats {
            rootVM.toggleArchived(chat, isCurrentlyArchived: isCurrentlyArchived)
        }
        endEditing()
    }

    private func performBulkDelete() {
        for chat in selectedChats {
            rootVM.deleteChat(chat, forAll: false)
        }
        endEditing()
    }

    private func endEditing() {
        withAnimation {
            isEditing = false
            selectedChatIds.removeAll()
        }
    }
}
