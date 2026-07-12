// FolderView.swift

import Combine
import SwiftUI
import TDLibKit

struct FolderView: View {
    // MARK: Internal

    @State var folder: CustomFolder

    @Namespace var namespace
    @Environment(\.scenePhase) var scenePhase
    @State var rootVM = RootVM.shared
    @State var chatToMute: CustomChat?

    var chats: [CustomChat] {
        folder.chats
            .sorted { $0.position.order > $1.position.order }
            .filter {
                rootVM.query.isEmpty
                    || $0.chat.title.lowercased().contains(rootVM.query.lowercased())
                    || $0.user?.firstName.lowercased().contains(rootVM.query.lowercased()) == true
                    || $0.user?.lastName.lowercased().contains(rootVM.query.lowercased()) == true
            }
    }
    
    var body: some View {
        ScrollViewReader { scrollViewProxy in
            bodyView.onAppear { folder.scrollViewProxy = scrollViewProxy }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard case .active = newPhase else { return }
            Task.background {
                await chats.asyncForEach { customChat in
                    _ = try? await td.getChatHistory(
                        chatId: customChat.chat.id,
                        fromMessageId: 0,
                        limit: 30,
                        offset: 0,
                        onlyLocal: false,
                    )
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

            if chats.isEmpty {
                Text(rootVM.query.isEmpty ? "Empty folder :(" : "No chats found for \"\(rootVM.query)\"")
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(chats) { customChat in
                    Button {
                        navigationStorage.push(.customChat(customChat))
                    } label: {
                        ChatsListItemView(customChat: customChat)
                            .matchedGeometryEffect(id: customChat.chat.id, in: namespace)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(customChat.accessibilityDescription)
                    .accessibilityHint("Opens chat")
                    .accessibilityActions {
                        Button(customChat.chat.isMarkedAsUnread ? "Mark as Read" : "Mark as Unread") {
                            toggleRead(for: customChat)
                        }
                        Button(customChat.isMuted ? "Unmute" : "Mute") {
                            toggleMuted(customChat)
                        }
                        Button(customChat.position.isPinned ? "Unpin" : "Pin") {
                            togglePinned(for: customChat)
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
                    .task {
                        _ = try? await td.getChatHistory(
                            chatId: customChat.chat.id,
                            fromMessageId: 0,
                            limit: 30,
                            offset: 0,
                            onlyLocal: false,
                        )
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
            Button("Mute forever") { muteSelectedChat(for: 400 * 24 * 60 * 60) }
            Button("Cancel", role: .cancel) { chatToMute = nil }
        }
    }
    
    @ViewBuilder func contextMenu(for customChat: CustomChat) -> some View {
        let isPinned = customChat.position.isPinned
        let isMarkedAsUnread = customChat.chat.isMarkedAsUnread
        Button(
            isMarkedAsUnread ? "Mark as Read" : "Mark as Unread",
            systemImage: isMarkedAsUnread
                ? "envelope.open"
                : "envelope.badge",
        ) {
            toggleRead(for: customChat)
        }

        Button(
            customChat.isMuted ? "Unmute" : "Mute",
            systemImage: customChat.isMuted ? "speaker.wave.2" : "speaker.slash",
        ) {
            toggleMuted(customChat)
        }

        Button(isPinned ? "Unpin" : "Pin", systemImage: isPinned ? "pin.slash.fill" : "pin.fill") {
            togglePinned(for: customChat)
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

    private func toggleRead(for customChat: CustomChat) {
        Task.background {
            try await td.toggleChatIsMarkedAsUnread(
                chatId: customChat.chat.id,
                isMarkedAsUnread: !customChat.chat.isMarkedAsUnread,
            )
        }
    }

    private func togglePinned(for customChat: CustomChat) {
        Task.background {
            try await td.toggleChatIsPinned(
                chatId: customChat.chat.id,
                chatList: folder.chatList,
                isPinned: !customChat.position.isPinned,
            )
        }
    }

    private func requestDelete(_ customChat: CustomChat) {
        rootVM.confirmChatDelete = ConfirmChatDelete(chat: customChat.chat, show: true)
    }

    private func toggleArchived(_ customChat: CustomChat) {
        let destination: ChatList = folder.type == .archive ? .chatListMain : .chatListArchive
        Task.background {
            try await td.addChatToList(chatId: customChat.chat.id, chatList: destination)
        }
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
        let current = customChat.notificationSettings
        let settings = ChatNotificationSettings(
            disableMentionNotifications: current.disableMentionNotifications,
            disablePinnedMessageNotifications: current.disablePinnedMessageNotifications,
            muteFor: duration,
            muteStories: current.muteStories,
            showPreview: current.showPreview,
            showStoryPoster: current.showStoryPoster,
            soundId: current.soundId,
            storySoundId: current.storySoundId,
            useDefaultDisableMentionNotifications: current.useDefaultDisableMentionNotifications,
            useDefaultDisablePinnedMessageNotifications: current.useDefaultDisablePinnedMessageNotifications,
            useDefaultMuteFor: false,
            useDefaultMuteStories: current.useDefaultMuteStories,
            useDefaultShowPreview: current.useDefaultShowPreview,
            useDefaultShowStoryPoster: current.useDefaultShowStoryPoster,
            useDefaultSound: current.useDefaultSound,
            useDefaultStorySound: current.useDefaultStorySound,
        )
        Task.background {
            try await td.setChatNotificationSettings(
                chatId: customChat.chat.id,
                notificationSettings: settings,
            )
        }
    }

    private let navigationStorage = NavigationStorage.shared
}
