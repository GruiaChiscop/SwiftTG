// MacSessionModel+ChatInfo.swift

import TDLibKit

extension MacSessionModel {
    func loadChatInfo(for state: ChatListItemState) async -> TelegramChatInfoData? {
        try? await TelegramChatInfoLoader(service: service).load(chatId: state.chatId)
    }

    func setChatInfoBlocked(_ blocked: Bool, userId: Int64) async -> Bool {
        messageActionError = nil
        do {
            _ = try await service.setMessageSenderBlockList(
                blockList: blocked ? .blockListMain : nil,
                senderId: .messageSenderUser(.init(userId: userId)),
            )
            return true
        } catch {
            messageActionError = error.localizedDescription
            return false
        }
    }

    func leaveChatFromInfo(_ chat: ChatListItemState) async -> Bool {
        messageActionError = nil
        do {
            _ = try await service.leaveChat(chatId: chat.chatId)
            _ = try await service.deleteChatHistory(
                chatId: chat.chatId,
                removeFromChatList: true,
                revoke: false,
            )
            return true
        } catch {
            messageActionError = error.localizedDescription
            return false
        }
    }

    func deleteCommunityFromInfo(_ chat: ChatListItemState) async -> Bool {
        messageActionError = nil
        do {
            _ = try await service.deleteChat(chatId: chat.chatId)
            return true
        } catch {
            messageActionError = error.localizedDescription
            return false
        }
    }

    func activateChatInfoMember(_ senderId: MessageSender) {
        Task { [weak self] in
            guard let self else { return }
            let chat: Chat? =
                switch senderId {
                case .messageSenderUser(let value):
                    try? await service.createPrivateChat(force: false, userId: value.userId)
                case .messageSenderChat(let value):
                    try? await service.getChat(chatId: value.chatId)
                }
            guard let chat else {
                messageActionError = "This member is private or unavailable."
                return
            }
            await activateResolvedChat(chat, messageId: nil)
        }
    }

    func activateChatInfoChat(_ chat: Chat) {
        Task { [weak self] in
            await self?.activateResolvedChat(chat, messageId: nil)
        }
    }

    func requestBotPrivacyPolicy(chatId: Int64) {
        performMessageAction {
            _ = try await self.service.sendMessage(
                chatId: chatId,
                inputMessageContent: .inputMessageText(.init(
                    clearDraft: false,
                    linkPreviewOptions: nil,
                    text: FormattedText(entities: [], text: "/privacy"),
                )),
                options: nil,
                replyMarkup: nil,
                replyTo: nil,
                topicId: nil,
            )
        }
    }
}
