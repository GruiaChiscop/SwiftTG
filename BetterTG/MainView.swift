// MainView.swift

import SwiftUI
import TDLibKit

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
        .navigationTitle("BetterTG")
        .searchable(
            text: $rootVM.query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search chats...",
        )
        .confirmationDialog(
            "Are you sure you want to delete chat with \(rootVM.confirmChatDelete.chat?.title ?? "User")?",
            isPresented: $rootVM.confirmChatDelete.show,
        ) {
            Button("Delete", role: .destructive) {
                guard let id = rootVM.confirmChatDelete.chat?.id else { return }
                Task.background { [rootVM] in
                    try await td.deleteChatHistory(
                        chatId: id, removeFromChatList: true, revoke: rootVM.confirmChatDelete.forAll,
                    )
                }
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
                case .customChat(let customChat):
                    ChatView(customChat: customChat)
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
                navigationStorage.push(.customChat(chat))
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
