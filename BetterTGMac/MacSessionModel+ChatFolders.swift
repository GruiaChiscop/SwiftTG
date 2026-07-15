import TDLibKit

extension MacSessionModel {
    var availableChatFolders: [MacChatFolder] {
        macChatFolders(from: chatList)
    }

    var selectedChatList: ChatList {
        availableChatFolders.first(where: { $0.id == selectedChatFolderId })?.chatList ?? .chatListMain
    }

    func selectChatFolder(_ folder: MacChatFolder) {
        guard selectedChatFolderId != folder.id else { return }
        selectedChatFolderId = folder.id
        focusedChatId = nil
        bootstrapChats()
    }

    func applyChatListSnapshot(_ snapshot: ChatListSnapshot) {
        chatList = snapshot
        if !availableChatFolders.contains(where: { $0.id == selectedChatFolderId }) {
            selectedChatFolderId = .main
            focusedChatId = nil
        }
        bootstrapChats()
    }

    func bootstrapChats() {
        guard bootstrapTask == nil else { return }
        guard let selectedFolder = availableChatFolders.first(where: { $0.id == selectedChatFolderId }),
              !loadedChatFolderIds.contains(selectedFolder.id)
        else {
            isLoadingChats = false
            return
        }

        isLoadingChats = true
        bootstrapTask = Task { [weak self] in
            guard let self else { return }
            defer {
                bootstrapTask = nil
                isLoadingChats = false
                if selectedChatFolderId != selectedFolder.id {
                    bootstrapChats()
                }
            }
            guard !Task.isCancelled,
                  let chatIds = try? await service.getChats(chatList: selectedFolder.chatList, limit: 200).chatIds
            else { return }
            loadedChatFolderIds.insert(selectedFolder.id)

            var loadedChats = [Chat]()
            let service = service
            await withTaskGroup(of: Chat?.self) { group in
                for chatId in chatIds {
                    group.addTask { [service] in
                        try? await service.getChat(chatId: chatId)
                    }
                }
                for await chat in group {
                    if let chat { loadedChats.append(chat) }
                }
            }
            guard !Task.isCancelled else { return }
            service.mergeChatListChats(loadedChats)
        }
    }
}
