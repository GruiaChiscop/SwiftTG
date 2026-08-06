// CustomFolder.swift

import SwiftUI
import TDLibKit

// MARK: - CustomFolder

@MainActor @Observable final class CustomFolder {
    // MARK: Lifecycle

    init(chats: [CustomChat], type: CustomFolderType) {
        self.chats = chats
        self.type = type
        self.folderId = Self.folderId(for: type)
    }
    
    // MARK: Internal

    enum CustomFolderType: Equatable, Hashable {
        case main
        case archive
        case folder(ChatFolderInfo, ChatFolder)
    }

    var chats: [CustomChat]
    var type: CustomFolderType
    /// Mirrors `id` as a plain immutable `Int` set once at init, so callers that can't touch
    /// main-actor-isolated state (like `Route`'s `Hashable` conformance in `RootVM.swift`, itself
    /// nonisolated) can still read a folder's id - `type` itself is a mutable, non-`Sendable`
    /// property and can't be read from there.
    let folderId: Int
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

    // MARK: Private

    private static func folderId(for type: CustomFolderType) -> Int {
        switch type {
        case .main: 0
        case .archive: -1
        case .folder(let info, _): info.id
        }
    }
}

// MARK: Hashable

extension CustomFolder: Hashable {
    /// Same reasoning as `CustomChat.hash(into:)` - hashing `chats` recursively hashed every
    /// `CustomChat` in the folder (each of which hashed its own nested TDLib structs), which is
    /// exactly the O(n^2) cost the xctrace capture found during chat-list bootstrap. `.onChange(of:
    /// rootVM.folders)` (MainView.swift) only needs identity, not content, equality.
    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}

// MARK: Identifiable

extension CustomFolder: Identifiable {
    nonisolated var id: Int { folderId }
}

// MARK: Equatable

extension CustomFolder: Equatable {
    nonisolated static func == (lhs: CustomFolder, rhs: CustomFolder) -> Bool {
        lhs === rhs
    }
}
