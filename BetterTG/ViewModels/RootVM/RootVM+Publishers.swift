// RootVM+Publishers.swift

import SwiftUI
@preconcurrency import TDLibKit

extension RootVM {
    func setPublishers() {
        service.authorizationStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                switch state {
                case .authorizationStateReady:
                    withAnimation { self.loggedIn = true }
                    bootstrapChatListsIfReady()
                    Task { @MainActor [weak self] in
                        await self?.resumePendingNotificationOpen()
                    }
                    Task { @MainActor [weak self] in
                        await self?.processPendingShareRequests()
                    }
                    Task { @MainActor in
                        await TelegramLiveLocationManager.shared.resumeActiveShares()
                    }
                    Task { [weak self] in
                        guard let self else { return }
                        await TelegramNotificationSoundCacheRefresh.refreshAll(service: service)
                    }
                case .authorizationStateWaitCode,
                     .authorizationStateWaitEmailAddress,
                     .authorizationStateWaitEmailCode,
                     .authorizationStateWaitOtherDeviceConfirmation,
                     .authorizationStateWaitPassword,
                     .authorizationStateWaitPhoneNumber,
                     .authorizationStateWaitPremiumPurchase,
                     .authorizationStateWaitRegistration:
                    resetForSignedOutState()
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
        service.updatePublisher
            .compactMap { update -> UpdateNotificationGroup? in
                guard case .updateNotificationGroup(let group) = update else { return nil }
                return group
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] group in
                self?.handleNotificationGroupUpdate(group)
            }
            .store(in: &cancellables)
        service.updatePublisher
            .compactMap { update -> UpdateUnconfirmedSession? in
                guard case .updateUnconfirmedSession(let value) = update else { return nil }
                return value
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.unconfirmedSession = value.session
            }
            .store(in: &cancellables)
    }

    /// A logged-out TDLib client passes through logging-out/closing/closed before a replacement
    /// client reaches a usable authorization step. Keep the current UI mounted during those
    /// terminal states, then clear all account-specific presentation state exactly when the new
    /// client is ready to accept login input.
    private func resetForSignedOutState() {
        chatListBootstrapTask?.cancel()
        chatListBootstrapTask = nil
        didBootstrapChatLists = false
        searchTask?.cancel()
        searchTask = nil
        searchGeneration &+= 1
        shareChatCacheWriteTask?.cancel()
        shareChatCacheWriteTask = nil
        shareRequestProcessingTask?.cancel()
        shareRequestProcessingTask = nil
        inAppNotificationDismissTask?.cancel()
        inAppNotificationDismissTask = nil

        withAnimation {
            loggedIn = false
            path.removeAll()
            folders.removeAll()
            archive = nil
            currentFolder = nil
        }
        query = ""
        searchChatResults = []
        searchGlobalChatResults = []
        searchMessageResults = []
        searchMessageChatTitles = [:]
        searchResultChatsById = [:]
        isSearching = false
        appliedChatListVersion = nil
        latestChatListSnapshot = .empty
        loadingChatKeys.removeAll()
        loadingFolderIds.removeAll()
        senderLoadVersions.removeAll()
        pendingDeepLinkJoin = nil
        pendingGroupCallJoin = nil
        pendingVideoChatJoin = nil
        deepLinkErrorMessage = nil
        inAppNotificationBanner = nil
        pendingInAppNotificationBanners.removeAll()
        unconfirmedSession = nil
        unconfirmedSessionActionError = nil
        isProcessingUnconfirmedSession = false
        discardPendingNotificationOpen()
        TelegramCurrentUserCache.shared.reset()
        ShareChatCache.save([])
    }

    // MARK: - Snapshot application

    func bootstrapChatListsIfReady() {
        guard !didBootstrapChatLists, chatListBootstrapTask == nil else { return }
        let service = service
        // Resolved eagerly (not lazily on first chat-list row) so `TelegramCurrentUserCache`'s
        // synchronous `userId` is already populated by the time rows render, avoiding a visible
        // name-then-"Saved Messages" flash.
        Task { await TelegramCurrentUserCache.shared.userId(service: service) }
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
        if let appliedChatListVersion, snapshot.version <= appliedChatListVersion {
            return
        }
        appliedChatListVersion = snapshot.version
        latestChatListSnapshot = snapshot
        applyFolders(snapshot)
        scheduleShareChatCacheUpdate()
    }

    /// Debounced (not written on every single snapshot delta, which can fire many times in a
    /// burst during initial sync) mirror of the top chats into the App Group's `ShareChatCache`,
    /// so the Share Extension - which has no TDLib access of its own - has something to show as
    /// its chat picker.
    private func scheduleShareChatCacheUpdate() {
        shareChatCacheWriteTask?.cancel()
        shareChatCacheWriteTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.writeShareChatCache()
        }
    }

    @MainActor private func writeShareChatCache() {
        let topChats = allChats
            .sorted { ($0.lastMessage?.date ?? 0) > ($1.lastMessage?.date ?? 0) }
            .prefix(60)
            .map { chat in
                ShareTargetChat(
                    id: chat.chat.id,
                    title: chat.displayTitle,
                    isSavedMessages: chat.isSavedMessages,
                    kind: Self.shareChatKind(chat.kind),
                )
            }
        ShareChatCache.save(Array(topChats))
    }

    private static func shareChatKind(_ kind: CustomChat.ChatKind) -> ShareChatKind {
        switch kind {
        case .bot, .privateChat: .privateChat
        case .group: .group
        case .channel: .channel
        }
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
        for folder in folders {
            applyChats(snapshot, to: folder)
        }
        if let archive {
            applyChats(snapshot, to: archive)
        }
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
        for index in 0...snapshot.chatFolders.count {
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
            Task.main {
                let chat = await self.getCustomChat(from: chatId, for: list)
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
        Task.main {
            let senderName = await self.getSenderName(for: item.lastMessage)
            guard self.senderLoadVersions[chatIdentifier] == messageId else { return }
            self.senderLoadVersions.removeValue(forKey: chatIdentifier)
            guard chat.lastMessage?.id == messageId,
                  self.isActive(chat)
            else { return }
            chat.lastMessageSenderName = senderName
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
