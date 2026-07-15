// RootVM+Publishers.swift

import SwiftUI
import TDLibKit

extension RootVM {
    func setPublishers() {
        service.authorizationStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                switch state {
                case .authorizationStateReady:
                    withAnimation { self.loggedIn = true }
                    self.bootstrapChatListsIfReady()
                case .authorizationStateClosed,
                     .authorizationStateClosing,
                     .authorizationStateLoggingOut,
                     .authorizationStateWaitPhoneNumber,
                     .authorizationStateWaitCode,
                     .authorizationStateWaitPassword:
                    withAnimation { self.loggedIn = false }
                default:
                    break
                }
            }
            .store(in: &cancellables)
        service.chatListPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                self?.apply(snapshot)
            }
            .store(in: &cancellables)
    }

    // MARK: - Snapshot application

    func bootstrapChatListsIfReady() {
        guard !didBootstrapChatLists, chatListBootstrapTask == nil else { return }
        let service = service
        chatListBootstrapTask = Task.background {
            guard let state = try? await service.getAuthorizationState(),
                  case .authorizationStateReady = state
            else {
                await main { self.chatListBootstrapTask = nil }
                return
            }

            var chatIds = Set<Int64>()
            var didLoadAnyList = false
            for list in [ChatList.chatListMain, .chatListArchive] {
                if let ids = try? await service.getChats(chatList: list, limit: 200).chatIds {
                    didLoadAnyList = true
                    chatIds.formUnion(ids)
                }
            }
            guard didLoadAnyList else {
                await main { self.chatListBootstrapTask = nil }
                return
            }
            let chats = await Array(chatIds).asyncCompactMap { chatId in
                try? await service.getChat(chatId: chatId)
            }
            service.mergeChatListChats(chats)
            await main {
                self.didBootstrapChatLists = true
                self.chatListBootstrapTask = nil
            }
        }
    }

    private func apply(_ snapshot: ChatListSnapshot) {
        if let appliedChatListVersion, snapshot.version <= appliedChatListVersion { return }
        appliedChatListVersion = snapshot.version
        latestChatListSnapshot = snapshot
        applyFolders(snapshot)
    }

    private func applyFolders(_ snapshot: ChatListSnapshot) {
        let snapshotFolderIds = Set(snapshot.chatFolders.map(\.id))
        let removedFolderIds = Set(folders.compactMap(\.info?.id)).subtracting(snapshotFolderIds)
        if !removedFolderIds.isEmpty {
            withAnimation {
                folders.removeAll { folder in folder.info.map { removedFolderIds.contains($0.id) } ?? false }
            }
        }

        if mainFolder == nil {
            folders.append(CustomFolder(chats: [], type: .main))
        }
        if archive == nil {
            archive = CustomFolder(chats: [], type: .archive)
        }

        for info in snapshot.chatFolders {
            if let existing = folders.first(where: { $0.info?.id == info.id }) {
                if existing.info != info {
                    loadFolder(info)
                }
            } else {
                loadFolder(info)
            }
        }

        reorderFolders(using: snapshot)
        for folder in folders { applyChats(snapshot, to: folder) }
        if let archive { applyChats(snapshot, to: archive) }
    }

    private func loadFolder(_ info: ChatFolderInfo) {
        guard loadingFolderIds.insert(info.id).inserted else { return }
        Task.background {
            let folder = try? await self.service.getChatFolder(chatFolderId: info.id)
            await main {
                self.loadingFolderIds.remove(info.id)
                guard let latestInfo = self.latestChatListSnapshot.chatFolders.first(where: { $0.id == info.id })
                else { return }

                guard latestInfo == info else {
                    self.loadFolder(latestInfo)
                    return
                }
                guard let folder else { return }

                if let existing = self.folders.first(where: { $0.info?.id == info.id }) {
                    withAnimation { existing.type = .folder(info, folder) }
                } else {
                    withAnimation {
                        self.folders.append(CustomFolder(chats: [], type: .folder(info, folder)))
                    }
                }
                self.reorderFolders(using: self.latestChatListSnapshot)
                if let loadedFolder = self.folders.first(where: { $0.info?.id == info.id }) {
                    self.applyChats(self.latestChatListSnapshot, to: loadedFolder)
                }
            }
        }
    }

    private func reorderFolders(using snapshot: ChatListSnapshot) {
        guard let mainFolder else { return }
        let customFolders = Dictionary(uniqueKeysWithValues: folders.compactMap { folder in
            folder.info.map { ($0.id, folder) }
        })
        var ordered = [CustomFolder]()
        for index in 0 ... snapshot.chatFolders.count {
            if index == snapshot.mainChatListPosition {
                ordered.append(mainFolder)
            }
            if index < snapshot.chatFolders.count,
               let folder = customFolders[snapshot.chatFolders[index].id]
            {
                ordered.append(folder)
            }
        }
        if !ordered.contains(where: { $0 === mainFolder }) {
            ordered.append(mainFolder)
        }
        if folders.map(\.id) != ordered.map(\.id) {
            withAnimation { folders = ordered }
        }
    }

    private func applyChats(_ snapshot: ChatListSnapshot, to folder: CustomFolder) {
        let list = folder.chatList
        let snapshotIds = Set(snapshot.chatIds(in: list))
        let currentIds = Set(folder.chats.map(\.id))

        let removedIds = currentIds.subtracting(snapshotIds)
        if !removedIds.isEmpty {
            withAnimation { folder.chats.removeAll { removedIds.contains($0.id) } }
        }

        let addedIds = snapshotIds.subtracting(currentIds)
        for chatId in addedIds {
            let key = ChatListLoadKey(chatId: chatId, list: list)
            guard loadingChatKeys.insert(key).inserted else { continue }
            Task.background {
                let chat = await self.getCustomChat(from: chatId, for: list)
                await main {
                    self.loadingChatKeys.remove(key)
                    guard self.isActive(folder),
                          self.latestChatListSnapshot.items[chatId]?.position(in: list) != nil,
                          !folder.chats.contains(where: { $0.id == chatId }),
                          let chat
                    else { return }
                    withAnimation { folder.chats.append(chat) }
                    if let item = self.latestChatListSnapshot.items[chatId],
                       let position = item.position(in: list)
                    {
                        self.applyChatChanges(item, position: position, to: chat)
                    }
                }
            }
        }

        for chat in folder.chats {
            guard let item = snapshot.items[chat.id], let position = item.position(in: list) else { continue }
            applyChatChanges(item, position: position, to: chat)
        }
    }

    private func applyChatChanges(_ item: ChatListItemState, position: ChatPosition, to chat: CustomChat) {
        let lastMessageChanged = chat.lastMessage != item.lastMessage
        guard chat.position != position
            || chat.unreadCount != item.unreadCount
            || chat.lastReadInboxMessageId != item.lastReadInboxMessageId
            || chat.isMarkedAsUnread != item.isMarkedAsUnread
            || chat.draftMessage != item.draftMessage
            || lastMessageChanged
            || (item.notificationSettings.map { $0 != chat.notificationSettings } ?? false)
        else { return }

        withAnimation {
            chat.position = position
            chat.unreadCount = item.unreadCount
            chat.lastReadInboxMessageId = item.lastReadInboxMessageId
            chat.isMarkedAsUnread = item.isMarkedAsUnread
            chat.draftMessage = item.draftMessage
            chat.lastMessage = item.lastMessage
            if let notificationSettings = item.notificationSettings {
                chat.notificationSettings = notificationSettings
            }
        }

        guard lastMessageChanged else { return }
        guard chat.showsLastMessageSender, let messageId = item.lastMessage?.id else {
            chat.lastMessageSenderName = nil
            senderLoadVersions.removeValue(forKey: ObjectIdentifier(chat))
            return
        }

        let chatIdentifier = ObjectIdentifier(chat)
        senderLoadVersions[chatIdentifier] = messageId
        Task.background {
            let senderName = await self.getSenderName(for: item.lastMessage)
            await main {
                guard self.senderLoadVersions[chatIdentifier] == messageId else { return }
                self.senderLoadVersions.removeValue(forKey: chatIdentifier)
                guard chat.lastMessage?.id == messageId,
                      self.isActive(chat)
                else { return }
                chat.lastMessageSenderName = senderName
            }
        }
    }

    private func isActive(_ folder: CustomFolder) -> Bool {
        archive === folder || folders.contains(where: { $0 === folder })
    }

    private func isActive(_ chat: CustomChat) -> Bool {
        folders.contains { $0.chats.contains(where: { $0 === chat }) }
            || archive?.chats.contains(where: { $0 === chat }) == true
    }
}
