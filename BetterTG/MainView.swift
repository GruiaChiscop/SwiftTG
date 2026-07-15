// MainView.swift

import SwiftUI

// MARK: - MainView

struct MainView: View {
    // MARK: Internal

    var body: some View {
        NavigationControllerWrapper(navigationController: navigationStorage.navigationController) {
            MainNavigationRootView()
        }
        .ignoresSafeArea()
    }

    // MARK: Private

    private let navigationStorage = NavigationStorage.shared
}

// MARK: - MainNavigationRootView

private struct MainNavigationRootView: View {
    // MARK: Internal

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
        .navigationTitle("SwiftTG")
        .searchable(
            text: $rootVM.query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search chats...",
        )
        .confirmationDialog(
            "Delete \(rootVM.confirmChatDelete.chat?.title ?? "chat")?",
            isPresented: $rootVM.confirmChatDelete.show,
        ) {
            if rootVM.confirmChatDelete.chat?.canBeDeletedOnlyForSelf == true {
                Button("Delete only for me", role: .destructive) {
                    rootVM.deleteSelectedChat(forAll: false)
                }
            }
            if rootVM.confirmChatDelete.chat?.canBeDeletedForAllUsers == true {
                Button("Delete for everyone", role: .destructive) {
                    rootVM.deleteSelectedChat(forAll: true)
                }
            }
            Button("Cancel", role: .cancel) {
                rootVM.confirmChatDelete = ConfirmChatDelete(chat: nil, show: false)
            }
        }
        .toolbar {
            if let archive = rootVM.archive {
                ToolbarItem(placement: .topBarLeading) {
                    Button(systemImage: "archivebox") {
                        navigationStorage.push(.archive(archive))
                    }
                    .accessibilityLabel("Archive")
                }
            }
        }
        .onAppear {
            navigationStorage.setDestinationBuilder { route in
                switch route {
                case .customChat(let customChat, let messageId):
                    ChatView(customChat: customChat, initialMessageId: messageId)
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
            #if DEBUG
            if MockData.isEnabled, CommandLine.arguments.contains("-mockChat"),
               let chat = rootVM.mainFolder?.chats.first
            {
                navigationStorage.push(.customChat(chat, messageId: nil))
            }
            #endif
            if rootVM.currentFolder == nil {
                rootVM.currentFolder = rootVM.folders.first?.id
            }
        }
        .onChange(of: rootVM.folders) {
            guard rootVM.currentFolder == nil else { return }
            rootVM.currentFolder = rootVM.folders.first?.id
        }
    }

    var currentFolder: CustomFolder? {
        rootVM.folders.first(where: { $0.id == rootVM.currentFolder }) ?? rootVM.folders.first
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
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    // MARK: Private

    @Bindable private var rootVM = RootVM.shared

    private let navigationStorage = NavigationStorage.shared
}
