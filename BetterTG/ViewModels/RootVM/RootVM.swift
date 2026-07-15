// RootVM.swift

import Combine
import SwiftUI
import TDLibKit

// MARK: - Route

enum Route: Hashable {
    case customChat(CustomChat, messageId: Int64? = nil)
    case archive(CustomFolder)
}

// MARK: - ChatListLoadKey

struct ChatListLoadKey: Hashable, Sendable {
    // MARK: Lifecycle

    init(chatId: Int64, list: ChatList) {
        self.chatId = chatId
        self.listKey =
            switch list {
            case .chatListMain: .main
            case .chatListArchive: .archive
            case .chatListFolder(let folder): .folder(folder.chatFolderId)
            }
    }

    // MARK: Internal

    enum ListKey: Hashable, Sendable {
        case main
        case archive
        case folder(Int)
    }

    let chatId: Int64
    let listKey: ListKey
}

// MARK: - RootVM

@Observable final class RootVM {
    // MARK: Lifecycle

    init(service: any TelegramService = TDLib.shared.service) {
        self.service = service
        setPublishers()
        bootstrapChatListsIfReady()
    }
    
    // MARK: Internal

    @ObservationIgnored static let shared = RootVM()
    
    var path = [Route]()
    var confirmChatDelete = ConfirmChatDelete(chat: nil, show: false)
    var folders = [CustomFolder]()
    var archive: CustomFolder?
    var currentFolder: Int?
    var query = ""
    var searchChatResults = [CustomChat]()
    var searchMessageResults = [Message]()
    var searchMessageChatTitles = [Int64: String]()
    var searchResultChatsById = [Int64: CustomChat]()
    var isSearching = false
    @ObservationIgnored var cancellables = Set<AnyCancellable>()
    @ObservationIgnored let service: any TelegramService
    @ObservationIgnored var appliedChatListVersion: UInt64?
    @ObservationIgnored var latestChatListSnapshot = ChatListSnapshot.empty
    @ObservationIgnored var loadingChatKeys = Set<ChatListLoadKey>()
    @ObservationIgnored var loadingFolderIds = Set<Int>()
    @ObservationIgnored var senderLoadVersions = [ObjectIdentifier: Int64]()
    @ObservationIgnored var chatListBootstrapTask: Task<Void, Never>?
    @ObservationIgnored var didBootstrapChatLists = false
    @ObservationIgnored var searchTask: Task<Void, Never>?
    @ObservationIgnored var searchGeneration: UInt64 = 0
    
    var loggedIn: Bool {
        get {
            access(keyPath: \.loggedIn)
            return UserDefaults.standard.bool(forKey: "loggedIn")
        }
        set {
            withMutation(keyPath: \.loggedIn) {
                UserDefaults.standard.set(newValue, forKey: "loggedIn")
            }
        }
    }
    
    var mainFolder: CustomFolder? { folders.first(where: { $0.type == .main }) }
    var allChats: [CustomChat] {
        var chats = [CustomChat]()
        if let archive {
            chats.append(contentsOf: archive.chats)
        }
        if let mainFolder {
            chats.append(contentsOf: mainFolder.chats)
        }
        return chats
    }
    
    func getCustomChat(from id: Int64, for chatList: ChatList) async -> CustomChat? {
        guard let chat = try? await service.getChat(chatId: id),
              let position = chat.positions.first(chatList) else { return nil }
        return await makeCustomChat(from: chat, position: position)
    }

    func getCustomChat(from id: Int64) async -> CustomChat? {
        if let existing = folders.lazy.flatMap(\.chats).first(where: { $0.chat.id == id })
            ?? archive?.chats.first(where: { $0.chat.id == id })
        {
            return existing
        }
        guard let chat = try? await service.getChat(chatId: id) else { return nil }
        let position = chat.positions.first ?? ChatPosition(
            isPinned: false,
            list: .chatListMain,
            order: 0,
            source: nil,
        )
        return await makeCustomChat(from: chat, position: position)
    }

    func getPrivateCustomChat(userId: Int64) async -> CustomChat? {
        guard let chat = try? await service.createPrivateChat(force: false, userId: userId) else { return nil }
        return await getCustomChat(from: chat.id)
    }

    func getSenderName(for message: Message?) async -> String? {
        guard let message else { return nil }

        switch message.senderId {
        case .messageSenderUser(let sender):
            guard let user = try? await service.getUser(userId: sender.userId) else { return nil }
            return "\(user.firstName) \(user.lastName)".trimmingCharacters(in: .whitespaces)
        case .messageSenderChat(let sender):
            return try? await service.getChat(chatId: sender.chatId).title
        }
    }
    
    func getCustomFolder(from info: ChatFolderInfo) async -> CustomFolder? {
        guard let folder = try? await service.getChatFolder(chatFolderId: info.id),
              let customChats = await getCustomChats(for: .chatListFolder(.init(chatFolderId: info.id)))
        else { return nil }
        return CustomFolder(
            chats: customChats,
            type: .folder(info, folder),
        )
    }
    
    func getCustomChats(for chatList: ChatList) async -> [CustomChat]? {
        guard let chatIds = try? await service.getChats(chatList: chatList, limit: 200).chatIds else { return nil }
        return await chatIds.asyncCompactMap { await getCustomChat(from: $0, for: chatList) }
    }

    // MARK: Private

    private func makeCustomChat(from chat: Chat, position: ChatPosition) async -> CustomChat? {
        switch chat.type {
        case .chatTypePrivate(let chatTypePrivate):
            guard let user = try? await service.getUser(userId: chatTypePrivate.userId) else { return nil }
            switch user.type {
            case .userTypeRegular:
                return CustomChat(
                    chat: chat,
                    position: position,
                    unreadCount: chat.unreadCount,
                    type: .user(user),
                    lastMessage: chat.lastMessage,
                    draftMessage: chat.draftMessage,
                )
            case .userTypeBot(let userTypeBot):
                return CustomChat(
                    chat: chat,
                    position: position,
                    unreadCount: chat.unreadCount,
                    type: .bot(userTypeBot),
                    lastMessage: chat.lastMessage,
                    draftMessage: chat.draftMessage,
                )
            case .userTypeDeleted, .userTypeUnknown:
                return nil
            }
        case .chatTypeSupergroup(let chatTypeSupergroup):
            guard let supergroup = try? await service.getSupergroup(supergroupId: chatTypeSupergroup.supergroupId)
            else { return nil }
            let senderName: String? =
                if supergroup.isChannel {
                    nil
                } else {
                    await getSenderName(for: chat.lastMessage)
                }
            return CustomChat(
                chat: chat,
                position: position,
                unreadCount: chat.unreadCount,
                type: .supergroup(supergroup),
                lastMessage: chat.lastMessage,
                lastMessageSenderName: senderName,
                draftMessage: chat.draftMessage,
            )
        case .chatTypeBasicGroup(let chatTypeBasicGroup):
            guard let group = try? await service.getBasicGroup(basicGroupId: chatTypeBasicGroup.basicGroupId)
            else { return nil }
            let senderName = await getSenderName(for: chat.lastMessage)
            return CustomChat(
                chat: chat,
                position: position,
                unreadCount: chat.unreadCount,
                type: .group(group),
                lastMessage: chat.lastMessage,
                lastMessageSenderName: senderName,
                draftMessage: chat.draftMessage,
            )
        default:
            return nil
        }
    }
}
