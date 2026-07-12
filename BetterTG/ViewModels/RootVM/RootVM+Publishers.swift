// RootVM+Publishers.swift

import SwiftUI
import TDLibKit

extension RootVM {
    func setPublishers() {
        nc.publisher(&cancellables, for: .updateChatFolders) { [weak self] updateChatFolders in
            guard let self else { return }
            self.updateChatFolders(updateChatFolders)
        }
        nc.publisher(&cancellables, for: .authorizationStateReady) { [weak self] _ in
            guard let self else { return }
            Task.main { withAnimation { self.loggedIn = true } }
        }
        nc.mergeMany(&cancellables, [
            .authorizationStateClosed,
            .authorizationStateClosing,
            .authorizationStateLoggingOut,
            .authorizationStateWaitPhoneNumber,
            .authorizationStateWaitCode,
            .authorizationStateWaitPassword,
        ]) { [weak self] _ in
            guard let self else { return }
            Task.main { withAnimation { self.loggedIn = false } }
        }
        nc.publisher(&cancellables, for: .updateChatReadInbox) { [weak self] updateChatReadInbox in
            guard let self,
                  let chat = allChats.first(where: { $0.chat.id == updateChatReadInbox.chatId }) else { return }
            Task.main { withAnimation { chat.unreadCount = updateChatReadInbox.unreadCount } }
        }
        nc.publisher(&cancellables, for: .updateNewChat) { [weak self] updateNewChat in
            guard let self else { return }
            self.updateNewChat(updateNewChat)
        }
        nc.publisher(&cancellables, for: .updateChatPosition) { [weak self] updateChatPosition in
            guard let self else { return }
            self.updateChatPosition(updateChatPosition)
        }
        nc.publisher(&cancellables, for: .updateChatDraftMessage) { [weak self] updateChatDraftMessage in
            guard let self else { return }
            self.updateChatDraftMessage(updateChatDraftMessage)
        }
        nc.publisher(&cancellables, for: .updateChatLastMessage) { [weak self] updateChatLastMessage in
            guard let self else { return }
            self.updateChatLastMessage(updateChatLastMessage)
        }
        nc.publisher(&cancellables, for: .updateChatNotificationSettings) { [weak self] update in
            guard let self else { return }
            for chat in allChats where chat.chat.id == update.chatId {
                Task.main { chat.notificationSettings = update.notificationSettings }
            }
        }
    }
    
    func updateChatFolders(_ updateChatFolders: UpdateChatFolders) {
        Task.background {
            var folders = await updateChatFolders.chatFolders.asyncCompactMap { await self.getCustomFolder(from: $0) }
            let mainFolder = await CustomFolder(chats: self.getCustomChats(for: .chatListMain) ?? [], type: .main)
            let archive = await CustomFolder(chats: self.getCustomChats(for: .chatListArchive) ?? [], type: .archive)
            folders.insert(mainFolder, at: updateChatFolders.mainChatListPosition)
            await main { [folders] in
                withAnimation {
                    self.folders = folders
                    self.archive = archive
                }
            }
        }
    }
    
    func updateNewChat(_ updateNewChat: UpdateNewChat) {
        Task.background {
            guard let customChat = await self.getCustomChat(from: updateNewChat.chat.id, for: .chatListMain)
            else { return }
            await main { withAnimation { self.mainFolder?.chats.append(customChat) } }
        }
    }
    
    func updateChatPosition(_ updateChatPosition: UpdateChatPosition) {
        let availableFolders = folders + (archive.map { [$0] } ?? [])
        guard let folder = availableFolders.first(where: { $0.chatList == updateChatPosition.position.list }) else {
            return
        }
        guard updateChatPosition.position.order != 0 else {
            Task.main { folder.chats.removeAll(where: { $0.chat.id == updateChatPosition.chatId }) }
            return
        }
        if let chat = folder.chats.first(where: { $0.chat.id == updateChatPosition.chatId }) {
            Task.main { withAnimation { chat.position = updateChatPosition.position } }
        } else {
            Task.background {
                guard let chat = await self.getCustomChat(
                    from: updateChatPosition.chatId,
                    for: updateChatPosition.position.list,
                ) else { return }
                await main { withAnimation { folder.chats.append(chat) } }
            }
        }
    }
    
    func updateChatDraftMessage(_ updateChatDraftMessage: UpdateChatDraftMessage) {
        for folder in folders {
            if let chat = folder.chats.first(where: { $0.chat.id == updateChatDraftMessage.chatId }),
               let position = updateChatDraftMessage.positions.first(folder.chatList)
            {
                Task.main {
                    withAnimation {
                        chat.draftMessage = updateChatDraftMessage.draftMessage
                        chat.position = position
                    }
                }
            }
        }
    }
    
    func updateChatLastMessage(_ updateChatLastMessage: UpdateChatLastMessage) {
        Task.background {
            let senderName = await self.getSenderName(for: updateChatLastMessage.lastMessage)
            await main {
                for folder in self.folders {
                    if let chat = folder.chats.first(where: { $0.chat.id == updateChatLastMessage.chatId }),
                       let position = updateChatLastMessage.positions.first(folder.chatList)
                    {
                        withAnimation {
                            chat.lastMessage = updateChatLastMessage.lastMessage
                            chat.lastMessageSenderName = chat.showsLastMessageSender ? senderName : nil
                            chat.position = position
                        }
                    }
                }
            }
        }
    }
}
