// RootVM+ChatActions.swift

import TDLibKit

extension RootVM {
    func toggleRead(for chat: CustomChat) {
        let chatId = chat.id
        let unreadCount = chat.unreadCount
        let lastMessageId = chat.lastMessage?.id
        let isMarkedAsUnread = chat.isMarkedAsUnread
        let service = service
        Task.background {
            await TelegramChatActions.toggleRead(
                service: service,
                chatId: chatId,
                unreadCount: unreadCount,
                lastMessageId: lastMessageId,
                isMarkedAsUnread: isMarkedAsUnread,
            )
        }
    }

    func togglePinned(for chat: CustomChat, in chatList: ChatList) {
        let chatId = chat.id
        let newIsPinned = !chat.position.isPinned
        let service = service
        Task.background {
            await TelegramChatActions.togglePinned(
                service: service,
                chatId: chatId,
                chatList: chatList,
                newIsPinned: newIsPinned,
            )
        }
    }

    func toggleArchived(_ chat: CustomChat, isCurrentlyArchived: Bool) {
        let chatId = chat.id
        let service = service
        Task.background {
            await TelegramChatActions.toggleArchived(
                service: service,
                chatId: chatId,
                isCurrentlyArchived: isCurrentlyArchived,
            )
        }
    }

    func requestDelete(_ chat: CustomChat) {
        confirmChatDelete = ConfirmChatDelete(
            chat: chat.chat,
            show: true,
            deletesCommunity: chat.actionPolicy.canDeleteCommunity,
        )
    }

    func requestLeave(_ chat: CustomChat) {
        confirmChatLeave = ConfirmChatLeave(chat: chat.chat, isChannel: chat.kind == .channel, show: true)
    }

    func leaveSelectedChat() {
        guard let chatId = confirmChatLeave.chat?.id else { return }
        confirmChatLeave = ConfirmChatLeave(chat: nil, isChannel: false, show: false)
        let service = service
        Task.background {
            await TelegramChatActions.leaveChat(service: service, chatId: chatId)
        }
    }

    func requestClearHistory(_ chat: CustomChat) {
        confirmChatClearHistory = ConfirmChatClearHistory(chat: chat.chat, show: true)
    }

    func clearSelectedChatHistory(forAll: Bool) {
        guard let chatId = confirmChatClearHistory.chat?.id else { return }
        confirmChatClearHistory = ConfirmChatClearHistory(chat: nil, show: false)
        let service = service
        Task.background {
            await TelegramChatActions.clearChatHistory(service: service, chatId: chatId, forEveryone: forAll)
        }
    }

    func deleteSelectedChat(forAll: Bool) {
        guard let chatId = confirmChatDelete.chat?.id else { return }
        let deletesCommunity = confirmChatDelete.deletesCommunity
        confirmChatDelete = ConfirmChatDelete(chat: nil, show: false)
        let service = service
        Task.background {
            if deletesCommunity {
                await TelegramChatActions.deleteCommunity(service: service, chatId: chatId)
            } else {
                await TelegramChatActions.deleteChatHistory(service: service, chatId: chatId, forEveryone: forAll)
            }
        }
    }

    func setMuteDuration(_ duration: Int, for chat: CustomChat) {
        let current = chat.notificationSettings
        let chatId = chat.id
        let service = service
        Task.background {
            await TelegramChatActions.setMuteDuration(
                service: service,
                chatId: chatId,
                duration: duration,
                current: current,
            )
        }
    }
}
