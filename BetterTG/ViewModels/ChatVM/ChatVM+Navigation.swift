// ChatVM+Navigation.swift

import SwiftUI
@preconcurrency import TDLibKit

extension ChatVM {
    func updateBottomVisibility(isLastMessageVisible: Bool) {
        isAtBottom = isLastMessageVisible
        let shouldShowButton = !isLastMessageVisible
        guard showScrollToBottomButton != shouldShowButton else { return }
        withAnimation { showScrollToBottomButton = shouldShowButton }
    }

    func scrollToLast() {
        guard let lastId = messages.last?.id, let scrollViewProxy else { return }
        withAnimation { scrollViewProxy.scrollTo(lastId, anchor: .bottom) }
    }

    func scrollTo(id: Int64?, anchor: UnitPoint = .center) {
        guard let scrollViewProxy, let id else { return }

        withAnimation {
            scrollViewProxy.scrollTo(id, anchor: anchor)
            highlightedMessageId = id
        }

        Task.main(delay: 0.5) {
            withAnimation {
                self.highlightedMessageId = nil
            }
        }
    }

    func navigateToMessage(id: Int64, movesAccessibilityFocus: Bool = false) {
        if messages.contains(where: { $0.id == id }) {
            if movesAccessibilityFocus {
                accessibilityFocusRequestMessageId = id
            } else {
                scrollRequestMessageId = id
            }
            return
        }

        loadingMessagesTask?.cancel()
        loadingMessagesGeneration += 1
        let generation = loadingMessagesGeneration
        pendingNavigationMessageId = id
        pendingNavigationMovesAccessibilityFocus = movesAccessibilityFocus
        let chatId = chatId
        loadingMessagesTask = Task.background {
            guard let history = try? await self.service.getChatHistory(
                chatId: chatId,
                fromMessageId: id,
                limit: 31,
                offset: -15,
                onlyLocal: false,
            ), !Task.isCancelled
            else {
                await main {
                    guard self.loadingMessagesGeneration == generation else { return }
                    self.pendingNavigationMessageId = nil
                    self.pendingNavigationMovesAccessibilityFocus = false
                    self.loadingMessagesTask = nil
                }
                return
            }
            let fetchedMessages = history.messages ?? []
            await main { self.loadedMessageIds.formUnion(fetchedMessages.map(\.id)) }
            self.service.mergeMessageHistory(
                chatId: chatId,
                messages: fetchedMessages,
            )
            await main {
                guard self.loadingMessagesGeneration == generation else { return }
                self.loadingMessagesTask = nil
            }
        }
    }

    func navigateToRepliedMessage(from message: Message) {
        guard case .messageReplyToMessage(let reply) = message.replyTo,
              reply.messageId != 0
        else { return }
        let chatId = reply.chatId == 0 ? customChat.chat.id : reply.chatId
        guard chatId != customChat.chat.id else {
            navigateToMessage(id: reply.messageId, movesAccessibilityFocus: true)
            return
        }
        openChat(chatId: chatId, messageId: reply.messageId, movesAccessibilityFocus: true)
    }

    func navigateToContact(userId: Int64) {
        Task { @MainActor [weak self] in
            guard let chat = await RootVM.shared.getPrivateCustomChat(userId: userId) else {
                self?.navigationError = "This contact can't be opened."
                return
            }
            RootVM.shared.navigate(to: .customChat(chat, messageId: nil))
        }
    }

    func navigateToForwardOrigin(from message: Message) {
        guard let origin = message.forwardInfo?.origin else { return }
        switch origin {
        case .messageOriginUser(let user):
            Task { @MainActor [weak self] in
                guard let chat = await RootVM.shared.getPrivateCustomChat(userId: user.senderUserId) else {
                    self?.navigationError = "This user can't be opened."
                    return
                }
                RootVM.shared.navigate(to: .customChat(chat, messageId: nil))
            }
        case .messageOriginChat(let chat):
            openChat(chatId: chat.senderChatId, messageId: nil)
        case .messageOriginChannel(let channel):
            openChat(chatId: channel.chatId, messageId: channel.messageId == 0 ? nil : channel.messageId)
        case .messageOriginHiddenUser:
            break
        }
    }

    // MARK: Private

    private func openChat(chatId: Int64, messageId: Int64?, movesAccessibilityFocus: Bool = false) {
        Task { @MainActor [weak self] in
            guard let chat = await RootVM.shared.getCustomChat(from: chatId) else {
                self?.navigationError = "This chat is private or unavailable."
                return
            }
            RootVM.shared.navigate(to: .customChat(
                chat,
                messageId: messageId,
                movesAccessibilityFocus: movesAccessibilityFocus,
            ))
        }
    }
}
