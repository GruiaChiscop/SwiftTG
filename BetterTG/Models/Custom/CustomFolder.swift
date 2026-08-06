// CustomFolder.swift

import SwiftUI
import TDLibKit

// MARK: - CustomFolder

@Observable final class CustomFolder {
    // MARK: Lifecycle

    init(chats: [CustomChat], type: CustomFolderType) {
        self.chats = chats
        self.type = type
    }
    
    // MARK: Internal

    enum CustomFolderType: Equatable, Hashable {
        case main
        case archive
        case folder(ChatFolderInfo, ChatFolder)
    }

    var chats: [CustomChat]
    var type: CustomFolderType
    var rect = CGRect.zero
    var scrollViewProxy: ScrollViewProxy?
    
    var chatList: ChatList {
        switch type {
        case .main: .chatListMain
        case .archive: .chatListArchive
        case .folder(let info, _): .chatListFolder(.init(chatFolderId: info.id))
        }
    }
    
    var name: String {
        switch type {
        case .main: "All"
        case .archive: "Archive"
        case .folder(let info, _): info.name.text.text
        }
    }
    
    var info: ChatFolderInfo? {
        switch type {
        case .folder(let info, _): info
        default: nil
        }
    }
    
    var folder: ChatFolder? {
        switch type {
        case .folder(_, let folder): folder
        default: nil
        }
    }
}

// MARK: Hashable

extension CustomFolder: Hashable {
    /// Same reasoning as `CustomChat.hash(into:)` - hashing `chats` recursively hashed every
    /// `CustomChat` in the folder (each of which hashed its own nested TDLib structs), which is
    /// exactly the O(n^2) cost the xctrace capture found during chat-list bootstrap. `.onChange(of:
    /// rootVM.folders)` (MainView.swift) only needs identity, not content, equality.
    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}

// MARK: Identifiable

extension CustomFolder: Identifiable {
    var id: Int {
        switch type {
        case .main: 0
        case .archive: -1
        case .folder(let info, _): info.id
        }
    }
}

// MARK: Equatable

extension CustomFolder: Equatable {
    static func == (lhs: CustomFolder, rhs: CustomFolder) -> Bool {
        lhs === rhs
    }
}
