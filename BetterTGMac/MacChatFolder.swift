// MacChatFolder.swift

import TDLibKit

// MARK: - MacChatFolderID

enum MacChatFolderID: Hashable, Sendable {
    case main
    case archive
    case folder(Int)
}

// MARK: - MacChatFolder

struct MacChatFolder: Identifiable, Hashable, Sendable {
    let id: MacChatFolderID
    let title: String

    var chatList: ChatList {
        switch id {
        case .main:
            .chatListMain
        case .archive:
            .chatListArchive
        case .folder(let folderId):
            .chatListFolder(.init(chatFolderId: folderId))
        }
    }
}

func macChatFolders(from snapshot: ChatListSnapshot) -> [MacChatFolder] {
    var folders = snapshot.chatFolders.map {
        MacChatFolder(id: .folder($0.id), title: $0.name.text.text)
    }
    let mainPosition = min(max(0, snapshot.mainChatListPosition), folders.count)
    folders.insert(MacChatFolder(id: .main, title: "All Chats"), at: mainPosition)
    folders.append(MacChatFolder(id: .archive, title: "Archive"))
    return folders
}
