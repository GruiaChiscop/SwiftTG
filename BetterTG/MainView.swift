// MainView.swift

import AVFoundation
import SwiftUI

// MARK: - MainView

struct MainView: View {
    // MARK: Internal

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Contacts", systemImage: "person.2.fill", value: MainTab.contacts) {
                NavigationStack {
                    ContactsView(service: rootVM.service)
                }
            }

            Tab("Calls", systemImage: "phone.fill", value: MainTab.calls) {
                NavigationStack {
                    CallsView(service: rootVM.service)
                }
            }

            Tab("Chats", systemImage: "bubble.left.and.bubble.right.fill", value: MainTab.chats) {
                NavigationStack(path: $rootVM.path) {
                    MainNavigationRootView()
                        .navigationDestination(for: Route.self) { route in
                            switch route {
                            case .customChat(let customChat, let messageId, let movesAccessibilityFocus):
                                // A forum-enabled supergroup shows its topic list first, matching
                                // Telegram-iOS - a link to a specific message still opens straight
                                // into the flat message stream it lives in.
                                if customChat.supergroup?.isForum == true, messageId == nil {
                                    ForumTopicsListView(customChat: customChat, service: rootVM.service)
                                } else {
                                    ChatView(
                                        customChat: customChat,
                                        initialMessageId: messageId,
                                        movesAccessibilityFocusToInitialMessage: movesAccessibilityFocus,
                                    )
                                }
                            case .archive(let customFolder):
                                FolderView(folder: customFolder)
                                    .navigationTitle(customFolder.name)
                                    .navigationBarTitleDisplayMode(.inline)
                                    .searchable(
                                        text: $rootVM.query,
                                        placement: .navigationBarDrawer(displayMode: .always),
                                        prompt: "Search archive...",
                                    )
                            }
                        }
                }
            }

            Tab("You", systemImage: "person.crop.circle", value: MainTab.you) {
                NavigationStack {
                    YouView(service: rootVM.service)
                }
            }
        }
        .onChange(of: rootVM.path) { _, path in
            if !path.isEmpty {
                selectedTab = .chats
            }
        }
    }

    // MARK: Private

    private enum MainTab: Hashable {
        case contacts
        case calls
        case chats
        case you
    }

    @Bindable private var rootVM = RootVM.shared
    @State private var selectedTab = MainTab.chats
}

// MARK: - MainNavigationRootView

private struct MainNavigationRootView: View {
    // MARK: Internal

    var currentFolder: CustomFolder? {
        rootVM.folders.first(where: { $0.id == rootVM.currentFolder }) ?? rootVM.folders.first
    }

    var body: some View {
        VStack(spacing: 0) {
            if rootVM.folders.count > 1 {
                folderTabsBar
            }

            if let currentFolder {
                FolderView(folder: currentFolder)
                    .id(currentFolder.id)
                    .transition(.opacity)
            }
        }
        .animation(.default, value: rootVM.currentFolder)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Chats")
        .searchable(
            text: $rootVM.query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search chats...",
        )
        .alert(
            "Delete \(rootVM.confirmChatDelete.chat?.title ?? "chat")?",
            isPresented: $rootVM.confirmChatDelete.show,
        ) {
            if rootVM.confirmChatDelete.deletesCommunity {
                Button("Delete for everyone", role: .destructive) {
                    rootVM.deleteSelectedChat(forAll: true)
                }
            } else if rootVM.confirmChatDelete.chat?.canBeDeletedOnlyForSelf == true {
                Button("Delete only for me", role: .destructive) {
                    rootVM.deleteSelectedChat(forAll: false)
                }
            }
            if !rootVM.confirmChatDelete.deletesCommunity,
               rootVM.confirmChatDelete.chat?.canBeDeletedForAllUsers == true
            {
                Button("Delete for everyone", role: .destructive) {
                    rootVM.deleteSelectedChat(forAll: true)
                }
            }
            Button("Cancel", role: .cancel) {
                rootVM.confirmChatDelete = ConfirmChatDelete(chat: nil, show: false)
            }
        }
        .confirmationDialog(
            "Clear history in \(rootVM.confirmChatClearHistory.chat?.title ?? "chat")?",
            isPresented: $rootVM.confirmChatClearHistory.show,
        ) {
            if rootVM.confirmChatClearHistory.chat?.canBeDeletedOnlyForSelf == true {
                Button("Clear only for me", role: .destructive) {
                    rootVM.clearSelectedChatHistory(forAll: false)
                }
            }
            if rootVM.confirmChatClearHistory.chat?.canBeDeletedForAllUsers == true {
                Button("Clear for everyone", role: .destructive) {
                    rootVM.clearSelectedChatHistory(forAll: true)
                }
            }
            Button("Cancel", role: .cancel) {
                rootVM.confirmChatClearHistory = ConfirmChatClearHistory(chat: nil, show: false)
            }
        } message: {
            Text("All messages will be removed, but the chat will remain in your chat list.")
        }
        .confirmationDialog(
            "Leave \(rootVM.confirmChatLeave.chat?.title ?? "chat")?",
            isPresented: $rootVM.confirmChatLeave.show,
        ) {
            Button(rootVM.confirmChatLeave.isChannel ? "Leave Channel" : "Leave Group", role: .destructive) {
                rootVM.leaveSelectedChat()
            }
            Button("Cancel", role: .cancel) {
                rootVM.confirmChatLeave = ConfirmChatLeave(chat: nil, isChannel: false, show: false)
            }
        } message: {
            Text("You will leave this chat and it will be removed from your chat list.")
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                TelegramNewChatMenu(service: rootVM.service) { chat in
                    Task {
                        guard let customChat = await rootVM.getCustomChat(from: chat.id) else { return }
                        rootVM.navigate(to: .customChat(customChat, messageId: nil))
                    }
                }
            }
            #if DEBUG
            ToolbarItem(placement: .topBarTrailing) {
                Button("Preview Login", systemImage: "person.crop.circle.badge.questionmark") {
                    showsLoginPreview = true
                }
            }
            #endif
        }
        #if DEBUG
        .sheet(isPresented: $showsLoginPreview) {
            NavigationStack {
                LoginView(isPreview: true)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") {
                                showsLoginPreview = false
                            }
                        }
                    }
            }
        }
        #endif
        .onAppear {
                if rootVM.currentFolder == nil {
                    rootVM.currentFolder = rootVM.folders.first?.id
                }
            }
            .onChange(of: rootVM.folders) {
                guard rootVM.currentFolder == nil else { return }
                rootVM.currentFolder = rootVM.folders.first?.id
            }
    }

    var folderTabsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(rootVM.folders) { folder in
                    let isSelected = rootVM.currentFolder == folder.id
                    Button {
                        withAnimation { rootVM.currentFolder = folder.id }
                    } label: {
                        Text(folder.name)
                            .font(.subheadline)
                            .fontWeight(isSelected ? .semibold : .regular)
                            .foregroundStyle(isSelected ? .white : .gray)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background {
                                if isSelected {
                                    Capsule().fill(.blue)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    // MARK: Private

    @Bindable private var rootVM = RootVM.shared
    #if DEBUG
    @State private var showsLoginPreview = false
    #endif
}
