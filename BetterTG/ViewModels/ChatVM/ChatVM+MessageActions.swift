// ChatVM+MessageActions.swift

import SwiftUI
import TDLibKit

extension ChatVM {
    func deleteMessage(id: Int64, deleteForBoth: Bool) {
        guard let customMessage = messages.first(where: { $0.message.id == id }) else { return }
        let messageIds = customMessage.album.isEmpty ? [id] : customMessage.album.map(\.id)
        performMessageAction(failureMessage: "Message couldn't be deleted") {
            try await TelegramMessageActions.delete(
                service: self.service,
                chatId: self.customChat.chat.id,
                messageIds: messageIds,
                forEveryone: deleteForBoth,
            )
        }
    }

    func reply(to message: CustomMessage?) {
        withAnimation { replyMessage = message }
    }

    func edit(_ message: CustomMessage?) {
        if message != nil {
            displayedImages.removeAll()
            composer.discardDisplayedDocuments()
        }
        setEditMessageText(from: message?.message)
        withAnimation { editCustomMessage = message }
    }

    func togglePinnedMessage(_ message: Message) {
        let action = message.isPinned ? "unpinned" : "pinned"
        performMessageAction(failureMessage: "Message couldn't be \(action)") {
            try await TelegramMessageActions.togglePinned(service: self.service, message: message)
        }
    }

    func forward(_ message: CustomMessage) {
        messagePendingForward = message
    }

    @discardableResult func forwardMessage(_ message: CustomMessage, to chat: CustomChat) async -> Bool {
        let messageIds = message.album.isEmpty ? [message.id] : message.album.map(\.id)
        do {
            try await TelegramMessageActions.forward(
                service: service,
                messageIds: messageIds,
                fromChatId: customChat.chat.id,
                toChatId: chat.chat.id,
            )
            return true
        } catch {
            return false
        }
    }

    /// Forwards to every chat concurrently rather than one at a time, so picking several
    /// destinations doesn't make the last one wait on all the earlier round trips.
    @discardableResult func forwardMessage(_ message: CustomMessage, to chats: [CustomChat]) async -> Bool {
        let succeededCount = await withTaskGroup(of: Bool.self) { group in
            for chat in chats {
                group.addTask { await self.forwardMessage(message, to: chat) }
            }
            return await group.reduce(into: 0) { count, succeeded in count += succeeded ? 1 : 0 }
        }
        if succeededCount < chats.count {
            await main {
                self.navigationError = succeededCount == 0
                    ? "This message couldn't be forwarded."
                    : "The message couldn't be forwarded to all the selected chats."
            }
        }
        return succeededCount == chats.count
    }

    @MainActor func toggleTranslation(_ customMessage: CustomMessage) {
        if customMessage.showsTranslation {
            withAnimation { customMessage.showsTranslation = false }
            return
        }
        ensureMessageTranslated(customMessage)
    }

    func toggleReaction(_ reaction: ReactionType, on message: Message) {
        performMessageAction(failureMessage: "Reaction couldn't be updated") {
            try await TelegramMessageActions.toggleReaction(
                service: self.service,
                message: message,
                reaction: reaction,
            )
        }
    }

    func performMessageAction(
        failureMessage: String,
        _ action: @escaping @Sendable () async throws -> Void,
    ) {
        messageActionError = nil
        Task.background {
            do {
                try await action()
            } catch {
                guard !Task.isCancelled else { return }
                await main {
                    self.messageActionError = "\(failureMessage): \(telegramErrorDescription(error))"
                }
            }
        }
    }
}
