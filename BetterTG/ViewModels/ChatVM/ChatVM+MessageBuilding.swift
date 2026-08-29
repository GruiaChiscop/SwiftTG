// ChatVM+MessageBuilding.swift

@preconcurrency import TDLibKit

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
                case .messageCall, .messageGroupCall, .messagePoll, .messageSticker, .messageVideoNote:
                    nil
                default:
                    FormattedText(entities: [], text: telegramMessageContentDescription(message))
                }
            }

        let customMessage = CustomMessage(
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
        )
        loadAvailableReactions(for: customMessage)
        loadTranslationEligibility(for: customMessage)
        return customMessage
    }

    /// `telegramMessageCanBeTranslated` runs `NLLanguageRecognizer` (on-device ML inference) -
    /// real CPU work, not just an RPC wait. Computing it synchronously for every message while
    /// building a chat's initial batch (up to 45 messages, several concurrently per
    /// `messageRenderLimiter`) pegs the CPU right when a chat opens, for a value only the
    /// context menu's Translate action ever reads - never the render path. Off the batch's
    /// critical path, same as `loadAvailableReactions` above.
    @discardableResult func loadTranslationEligibility(for customMessage: CustomMessage) -> Task<Void, Never> {
        let message = customMessage.message
        let chatType = customChat.chat.type
        return Task.background {
            let canBeTranslated = telegramMessageCanBeTranslated(message, chatType: chatType)
            Task { @MainActor in
                customMessage.canBeTranslated = canBeTranslated
            }
        }
    }

    /// Fetching a message's available reactions can require a server round trip (the reaction
    /// set depends on chat/boost/premium state TDLib doesn't always have cached), and it's only
    /// ever read from the reaction picker/quick-react row - never from the render path itself.
    /// Doing this off the critical path that gates a chat's initial "loaded" state (unlike the
    /// other fields above) keeps that gate from waiting on a call nothing shows during load.
    @discardableResult func loadAvailableReactions(for customMessage: CustomMessage) -> Task<Void, Never> {
        let chatId = customChat.chat.id
        let messageId = customMessage.id
        return Task.main {
            guard let reactions = try? await self.service.getMessageAvailableReactions(
                chatId: chatId,
                messageId: messageId,
                rowSize: 8,
            ) else { return }
            customMessage.availableReactions = telegramAvailableReactions(reactions)
        }
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
