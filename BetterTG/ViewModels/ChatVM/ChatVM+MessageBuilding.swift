// ChatVM+MessageBuilding.swift

import TDLibKit

extension ChatVM {
    func getCustomMessage(fromId id: Int64) async -> CustomMessage? {
        guard let message = try? await service.getMessage(chatId: customChat.chat.id, messageId: id) else { return nil }
        return await getCustomMessage(from: message)
    }

    func getCustomMessage(from message: Message) async -> CustomMessage {
        async let replyToMessageTask = getReplyToMessage(message.replyTo)
        async let forwardedFromTask = getForwardedFrom(message.forwardInfo?.origin)
        async let propertiesTask = service.getMessageProperties(
            chatId: customChat.chat.id, messageId: message.id,
        )
        async let reactionsTask = service.getMessageAvailableReactions(
            chatId: customChat.chat.id,
            messageId: message.id,
            rowSize: 8,
        )
        async let senderUserTask = resolvedSenderUser(for: message.senderId)
        async let serviceMessageTextTask = TelegramServiceMessage.description(service: service, message: message)

        let replyToMessage = await replyToMessageTask
        let forwardedFrom = await forwardedFromTask
        let properties = await (try? propertiesTask) ?? .default
        let senderUser = await senderUserTask
        let senderChatTitle: String? =
            if case .messageSenderChat = message.senderId {
                await TelegramSenderName.displayName(
                    service: service,
                    senderId: message.senderId,
                )
            } else {
                nil
            }
        let serviceMessageText = await serviceMessageTextTask
        let availableReactions: [AvailableReaction] =
            if let reactions = try? await reactionsTask {
                telegramAvailableReactions(reactions)
            } else {
                []
            }

        let replyUser: User?
        let replySenderName: String?
        if case .messageSenderUser(let messageSenderUser) = replyToMessage?.senderId {
            replyUser = try? await service.getUser(userId: messageSenderUser.userId)
            replySenderName = replyUser.map(telegramUserDisplayName)
        } else if case .messageSenderChat(let messageSenderChat) = replyToMessage?.senderId {
            replyUser = nil
            replySenderName = try? await service.getChat(chatId: messageSenderChat.chatId).title
        } else {
            replyUser = nil
            replySenderName = nil
        }

        let formattedText: FormattedText? =
            if let serviceMessageText {
                FormattedText(entities: [], text: serviceMessageText)
            } else {
                switch message.content {
                case .messageText(let messageText):
                    messageText.text
                case .messageAudio, .messageDocument, .messagePhoto, .messageVideo, .messageVoiceNote:
                    telegramMessageFormattedText(message)
                case .messagePoll, .messageSticker:
                    nil
                default:
                    FormattedText(entities: [], text: telegramMessageContentDescription(message))
                }
            }

        return CustomMessage(
            message: message,
            senderUser: senderUser,
            senderChatTitle: senderChatTitle,
            replyUser: replyUser,
            replySenderName: replySenderName,
            replyToMessage: replyToMessage,
            album: message.mediaAlbumId != 0 && telegramMessageSupportsVisualAlbum(message) ? [message] : [],
            forwardedFrom: forwardedFrom,
            serviceMessageText: serviceMessageText,
            formattedText: formattedText,
            properties: properties,
            availableReactions: availableReactions,
        )
    }

    func resolvedSenderUser(for senderId: MessageSender) async -> User? {
        guard case .messageSenderUser(let sender) = senderId else { return nil }
        return try? await service.getUser(userId: sender.userId)
    }

    func getForwardedFrom(_ origin: MessageOrigin?) async -> String? {
        guard let origin else { return nil }
        return await TelegramMessageOrigin.displayName(service: service, origin: origin)
    }

    func getReplyToMessage(_ replyTo: MessageReplyTo?) async -> Message? {
        if case .messageReplyToMessage(let messageReplyToMessage) = replyTo, messageReplyToMessage.messageId != 0 {
            return try? await service.getMessage(
                chatId: messageReplyToMessage.chatId == 0
                    ? customChat.chat.id
                    : messageReplyToMessage.chatId,
                messageId: messageReplyToMessage.messageId,
            )
        }
        return nil
    }

    func getInputReplyToMessage(_ inputMessageReplyTo: InputMessageReplyTo?) async -> CustomMessage? {
        if case .inputMessageReplyToMessage(let message) = inputMessageReplyTo {
            return await getCustomMessage(fromId: message.messageId)
        }
        return nil
    }
}
