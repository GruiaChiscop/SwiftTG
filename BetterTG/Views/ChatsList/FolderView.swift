// FolderView.swift

import SwiftUI

struct FolderView: View {
    // MARK: Internal

    @State var folder: CustomFolder

    @Namespace var namespace
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
                    Button {
                        navigationStorage.push(.customChat(customChat, messageId: nil))
                    } label: {
                        ChatsListItemView(customChat: customChat)
                            .matchedGeometryEffect(id: customChat.chat.id, in: namespace)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(customChat.accessibilityDescription)
                    .accessibilityHint("Opens chat")
                    .accessibilityActions {
                        Button(customChat.hasUnreadMessages ? "Mark as Read" : "Mark as Unread") {
                            rootVM.toggleRead(for: customChat)
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
                        if customChat.chat.canBeDeletedOnlyForSelf
                            || customChat.chat.canBeDeletedForAllUsers
                        {
                            Button("Delete") {
                                requestDelete(customChat)
                            }
                        }
                    }
                    .contextMenu {
                        contextMenu(for: customChat)
                    } preview: {
                        LazyView {
                            NavigationControllerWrapper {
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
        .scrollIndicators(.visible)
        .confirmationDialog(
            "Mute \(chatToMute?.chat.title ?? "chat")",
            isPresented: Binding(
                get: { chatToMute != nil },
                set: { if !$0 { chatToMute = nil } },
            ),
        ) {
            Button("Mute for 1 hour") { muteSelectedChat(for: 60 * 60) }
            Button("Mute for 8 hours") { muteSelectedChat(for: 8 * 60 * 60) }
            Button("Mute for 2 days") { muteSelectedChat(for: 2 * 24 * 60 * 60) }
            Button("Mute forever") { muteSelectedChat(for: Int(Int32.max)) }
            Button("Cancel", role: .cancel) { chatToMute = nil }
        }
    }

    @ViewBuilder private var searchResults: some View {
        if !rootVM.searchChatResults.isEmpty {
            Section {
                ForEach(rootVM.searchChatResults) { customChat in
                    Button {
                        navigationStorage.push(.customChat(customChat, messageId: nil))
                    } label: {
                        ChatsListItemView(customChat: customChat)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens chat")
                }
            } header: {
                Text("Chats (\(rootVM.searchChatResults.count))")
                    .font(.headline)
                    .accessibilityLabel("Chats, \(rootVM.searchChatResults.count) found")
                    .accessibilityAddTraits(.isHeader)
            }
        }

        if !rootVM.searchMessageResults.isEmpty {
            Section {
                ForEach(Array(rootVM.searchMessageResults.enumerated()), id: \.offset) { _, message in
                    if let customChat = rootVM.searchResultChatsById[message.chatId] {
                        Button {
                            navigationStorage.push(.customChat(customChat, messageId: message.id))
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(rootVM.searchMessageChatTitles[message.chatId] ?? customChat.chat.title)
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
                        .accessibilityHint("Opens this message in the chat")
                    }
                }
            } header: {
                Text("Messages (\(rootVM.searchMessageResults.count))")
                    .font(.headline)
                    .accessibilityLabel("Messages, \(rootVM.searchMessageResults.count) found")
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
    
    @ViewBuilder func contextMenu(for customChat: CustomChat) -> some View {
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
            customChat.isMuted ? "Unmute" : "Mute",
            systemImage: customChat.isMuted ? "speaker.wave.2" : "speaker.slash",
        ) {
            toggleMuted(customChat)
        }

        Button(isPinned ? "Unpin" : "Pin", systemImage: isPinned ? "pin.slash.fill" : "pin.fill") {
            rootVM.togglePinned(for: customChat, in: folder.chatList)
        }

        Button(
            folder.type == .archive ? "Unarchive" : "Archive",
            systemImage: folder.type == .archive ? "tray.and.arrow.up" : "archivebox",
        ) {
            toggleArchived(customChat)
        }

        if customChat.chat.canBeDeletedOnlyForSelf || customChat.chat.canBeDeletedForAllUsers {
            Button("Delete", systemImage: "trash", role: .destructive) {
                requestDelete(customChat)
            }
        }
    }

    // MARK: Private

    private func requestDelete(_ customChat: CustomChat) {
        rootVM.requestDelete(customChat)
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

    private let navigationStorage = NavigationStorage.shared
}
