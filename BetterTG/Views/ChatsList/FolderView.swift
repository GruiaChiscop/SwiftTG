// FolderView.swift

import SwiftUI

struct FolderView: View {
    // MARK: Internal

    @State var folder: CustomFolder

    @State var rootVM = RootVM.shared
    @State var chatToMute: CustomChat?

    var chats: [CustomChat] {
        folder.chats
            .sorted { $0.position.order > $1.position.order }
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

            if !rootVM.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                searchResults
            } else if chats.isEmpty {
                Text("Empty folder")
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(chats) { customChat in
                    NavigationLink(value: Route.customChat(customChat, messageId: nil)) {
                        ChatsListItemView(customChat: customChat)
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
        } else if rootVM.searchChatResults.isEmpty, rootVM.searchMessageResults.isEmpty {
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
}
