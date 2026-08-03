// MacSessionModel+ChatActions.swift

import TDLibKit

extension MacSessionModel {
    func toggleRead(for chat: ChatListItemState) {
        performMessageAction {
            await TelegramChatActions.toggleRead(
                service: self.service,
                chatId: chat.chatId,
                unreadCount: chat.unreadCount,
                lastMessageId: chat.lastMessage?.id,
                isMarkedAsUnread: chat.isMarkedAsUnread,
            )
        }
    }

    func togglePinned(for chat: ChatListItemState, in chatList: ChatList) {
        let isPinned = chat.position(in: chatList)?.isPinned == true
        performMessageAction {
            await TelegramChatActions.togglePinned(
                service: self.service,
                chatId: chat.chatId,
                chatList: chatList,
                newIsPinned: !isPinned,
            )
        }
    }

    func toggleArchived(_ chat: ChatListItemState) {
        let isArchived = chat.position(in: .chatListArchive) != nil
        performMessageAction {
            await TelegramChatActions.toggleArchived(
                service: self.service,
                chatId: chat.chatId,
                isCurrentlyArchived: isArchived,
            )
        }
    }

    func setMuteDuration(_ duration: Int, for chat: ChatListItemState) {
        guard let current = chat.notificationSettings else { return }
        performMessageAction {
            await TelegramChatActions.setMuteDuration(
                service: self.service,
                chatId: chat.chatId,
                duration: duration,
                current: current,
            )
        }
    }

    func deleteChat(_ chat: ChatListItemState, forEveryone: Bool) {
        performMessageAction {
            await TelegramChatActions.deleteChatHistory(
                service: self.service,
                chatId: chat.chatId,
                forEveryone: forEveryone,
            )
        }
    }

    func clearChatHistory(_ chat: ChatListItemState, forEveryone: Bool) {
        performMessageAction {
            await TelegramChatActions.clearChatHistory(
                service: self.service,
                chatId: chat.chatId,
                forEveryone: forEveryone,
            )
        }
    }

    func leaveChat(_ chat: ChatListItemState) {
        performMessageAction {
            await TelegramChatActions.leaveChat(service: self.service, chatId: chat.chatId)
        }
    }

    func toggleReaction(_ reaction: ReactionType, on message: Message) {
        performMessageAction {
            try await TelegramMessageActions.toggleReaction(
                service: self.service,
                message: message,
                reaction: reaction,
            )
        }
    }

    func togglePin(for message: Message) {
        performMessageAction {
            try await TelegramMessageActions.togglePinned(service: self.service, message: message)
        }
    }

    func delete(_ message: Message, forEveryone: Bool) {
        performMessageAction {
            try await TelegramMessageActions.delete(
                service: self.service,
                chatId: message.chatId,
                messageIds: [message.id],
                forEveryone: forEveryone,
            )
        }
    }

    @discardableResult func forward(_ message: Message, to chatId: Int64) async -> Bool {
        do {
            try await TelegramMessageActions.forward(
                service: service,
                messageIds: [message.id],
                fromChatId: message.chatId,
                toChatId: chatId,
            )
            return true
        } catch {
            return false
        }
    }

    /// Forwards to every chat concurrently rather than one at a time, so picking several
    /// destinations doesn't make the last one wait on all the earlier round trips.
    @discardableResult func forward(_ message: Message, to chatIds: [Int64]) async -> Bool {
        let succeededCount = await withTaskGroup(of: Bool.self) { group in
            for chatId in chatIds {
                group.addTask { await self.forward(message, to: chatId) }
            }
            return await group.reduce(into: 0) { count, succeeded in count += succeeded ? 1 : 0 }
        }
        if succeededCount < chatIds.count {
            messageActionError = succeededCount == 0
                ? "This message couldn't be forwarded."
                : "The message couldn't be forwarded to all the selected chats."
        }
        return succeededCount == chatIds.count
    }

    func performMessageAction(_ action: @escaping @MainActor () async throws -> Void) {
        messageActionError = nil
        Task {
            do {
                try await action()
            } catch {
                messageActionError = error.localizedDescription
            }
        }
    }
}
