// MacSessionModel+MessageMetadata.swift

import TDLibKit

// MARK: - MacMessageCapabilities

struct MacMessageCapabilities {
    let properties: MessageProperties
}

// MARK: - MacMessageReplyContext

struct MacMessageReplyContext {
    let chatId: Int64
    let messageId: Int64?
    let senderName: String
    let quotedText: String
}

// MARK: - MacMessageSenderKey

enum MacMessageSenderKey: Hashable {
    case chat(Int64)
    case user(Int64)
}

extension MacSessionModel {
    func loadCapabilities(for message: Message) async {
        guard messageCapabilities[message.id] == nil,
              !loadingCapabilityMessageIds.contains(message.id),
              openedChatId == message.chatId
        else { return }
        loadingCapabilityMessageIds.insert(message.id)
        defer { loadingCapabilityMessageIds.remove(message.id) }

        guard let properties = try? await service.getMessageProperties(
            chatId: message.chatId,
            messageId: message.id,
        ), openedChatId == message.chatId
        else { return }

        messageCapabilities[message.id] = MacMessageCapabilities(
            properties: properties,
        )
    }

    func loadAvailableReactions(for message: Message) async {
        guard messageAvailableReactions[message.id] == nil,
              !loadingReactionMessageIds.contains(message.id),
              openedChatId == message.chatId
        else { return }
        loadingReactionMessageIds.insert(message.id)
        defer { loadingReactionMessageIds.remove(message.id) }

        guard let availableReactions = try? await service.getMessageAvailableReactions(
            chatId: message.chatId,
            messageId: message.id,
            rowSize: 8,
        ),
            openedChatId == message.chatId
        else { return }
        messageAvailableReactions[message.id] = telegramAvailableReactions(availableReactions)
    }

    func loadServiceDescription(for message: Message) async {
        guard TelegramServiceMessage.isServiceMessage(message.content),
              messageServiceDescriptions[message.id] == nil,
              !loadingServiceMessageIds.contains(message.id),
              openedChatId == message.chatId
        else { return }
        loadingServiceMessageIds.insert(message.id)
        defer { loadingServiceMessageIds.remove(message.id) }

        guard let description = await TelegramServiceMessage.description(service: service, message: message),
              openedChatId == message.chatId
        else { return }
        messageServiceDescriptions[message.id] = description
    }

    /// Computed once and cached, not on every render - language detection runs an on-device ML
    /// model (`NLLanguageRecognizer`), too expensive to call from `canTranslate` directly, which
    /// SwiftUI re-evaluates on every re-render of the row.
    func loadTranslationEligibility(for message: Message) {
        guard messageTranslationEligibility[message.id] == nil else { return }
        guard case .messageText = message.content else {
            messageTranslationEligibility[message.id] = false
            return
        }
        messageTranslationEligibility[message.id] = telegramMessageCanBeTranslated(
            message,
            chatType: openedChatType,
        )
    }

    func loadReplyContext(for message: Message) async {
        guard messageReplyContexts[message.id] == nil,
              !loadingReplyContextMessageIds.contains(message.id),
              case .messageReplyToMessage(let reply) = message.replyTo,
              openedChatId == message.chatId
        else { return }
        loadingReplyContextMessageIds.insert(message.id)
        defer { loadingReplyContextMessageIds.remove(message.id) }

        let repliedMessage: Message? =
            if reply.messageId != 0 {
                try? await service.getMessage(
                    chatId: reply.chatId == 0 ? message.chatId : reply.chatId,
                    messageId: reply.messageId,
                )
            } else {
                nil
            }

        let senderName: String =
            switch repliedMessage?.senderId {
            case .messageSenderUser(let sender):
                await (try? service.getUser(userId: sender.userId))?.firstName ?? "message"
            case .messageSenderChat(let sender):
                await (try? service.getChat(chatId: sender.chatId))?.title ?? "message"
            case nil:
                "message"
            }

        let quotedText: String =
            if let explicitQuote = reply.quote?.text.text, !explicitQuote.isEmpty {
                explicitQuote
            } else if let repliedMessage {
                telegramMessageContentDescription(repliedMessage)
            } else if let content = reply.content {
                telegramMessageContentDescription(content)
            } else {
                "Message"
            }
        guard openedChatId == message.chatId else { return }
        messageReplyContexts[message.id] = MacMessageReplyContext(
            chatId: reply.chatId == 0 ? message.chatId : reply.chatId,
            messageId: reply.messageId == 0 ? repliedMessage?.id : reply.messageId,
            senderName: senderName,
            quotedText: telegramQuotedMessageExcerpt(quotedText),
        )
    }

    func loadForwardedFrom(for message: Message) async {
        guard messageForwardedFrom[message.id] == nil,
              !loadingForwardedMessageIds.contains(message.id),
              let origin = message.forwardInfo?.origin,
              openedChatId == message.chatId
        else { return }
        loadingForwardedMessageIds.insert(message.id)
        defer { loadingForwardedMessageIds.remove(message.id) }

        let name = await TelegramMessageOrigin.displayName(service: service, origin: origin)
        guard openedChatId == message.chatId, let name, !name.isEmpty else { return }
        messageForwardedFrom[message.id] = name
    }

    func loadSenderName(for message: Message) async {
        guard !message.isOutgoing,
              messageSenderNames[message.id] == nil,
              openedChatId == message.chatId
        else { return }

        let resolvedSenderKey: MacMessageSenderKey =
            switch message.senderId {
            case .messageSenderUser(let sender):
                .user(sender.userId)
            case .messageSenderChat(let sender):
                .chat(sender.chatId)
            }
        if let cachedName = senderNamesByKey[resolvedSenderKey] {
            messageSenderNames[message.id] = cachedName
            return
        }
        let request: Task<String?, Never>
        let ownsRequest: Bool
        if let pendingRequest = senderNameRequests[resolvedSenderKey] {
            request = pendingRequest
            ownsRequest = false
        } else {
            let senderId = message.senderId
            request = Task { [service] in
                await TelegramSenderName.displayName(service: service, senderId: senderId)
            }
            senderNameRequests[resolvedSenderKey] = request
            ownsRequest = true
        }
        let name = await request.value
        if ownsRequest {
            senderNameRequests[resolvedSenderKey] = nil
        }
        guard let name, !name.isEmpty else { return }
        if !ownsRequest {
            guard openedChatId == message.chatId,
                  messageSenderNames[message.id] != name
            else { return }
            messageSenderNames[message.id] = name
            return
        }

        senderNamesByKey[resolvedSenderKey] = name
        guard openedChatId == message.chatId else { return }
        for visibleMessage in messages.messages.values where
            senderKey(for: visibleMessage) == resolvedSenderKey && messageSenderNames[visibleMessage.id] != name
        {
            messageSenderNames[visibleMessage.id] = name
        }
    }

    func cachedSenderName(for message: Message) -> String? {
        messageSenderNames[message.id] ?? senderNamesByKey[senderKey(for: message)]
    }

    func toggleTranslation(for message: Message) {
        if translationShownMessageIds.contains(message.id) {
            translationShownMessageIds.remove(message.id)
            return
        }
        ensureTranslation(for: message)
    }

    /// The shared "fetch, cache, show" primitive behind both the per-message Translate action and
    /// whole-chat translation - a no-op if already showing or already in flight.
    func ensureTranslation(for message: Message) {
        guard !translatingMessageIds.contains(message.id), !translationShownMessageIds.contains(message.id)
        else { return }
        if messageTranslations[message.id] != nil {
            translationShownMessageIds.insert(message.id)
            return
        }
        guard telegramMessageFormattedText(message) != nil else { return }

        translatingMessageIds.insert(message.id)
        let chatId = message.chatId
        let messageId = message.id
        let targetLanguageCode = telegramTranslationTargetLanguageCode()
        Task {
            defer { translatingMessageIds.remove(messageId) }
            do {
                let translatedText = try await service.translateMessageText(
                    chatId: chatId,
                    messageId: messageId,
                    toLanguageCode: targetLanguageCode,
                    tone: nil,
                )
                guard openedChatId == chatId else { return }
                messageTranslations[messageId] = translatedText
                translationShownMessageIds.insert(messageId)
            } catch {
                guard !Task.isCancelled, openedChatId == chatId else { return }
                messageActionError = "Message couldn't be translated: \(telegramErrorDescription(error))"
            }
        }
    }

    var showsChatTranslationBanner: Bool {
        guard let chatId = openedChatId else { return false }
        return !isChatTranslationEnabled
            && detectedChatLanguage != nil
            && !TelegramChatTranslationPreferences.isDismissed(chatId: chatId)
    }

    /// Called once a chat's initial history has loaded, so there's an actual sample to detect
    /// from - mirrors Telegram-iOS's own chat-language detection running against recently loaded
    /// history rather than a single message.
    func refreshDetectedChatLanguage() {
        guard let chatId = openedChatId else { return }
        let sample = messages.orderedMessageIds.compactMap { messages.messages[$0] }
        let targetLanguageCode = telegramTranslationTargetLanguageCode()
        Task {
            guard let detected = telegramDetectedChatLanguage(from: sample), detected != targetLanguageCode,
                  openedChatId == chatId
            else { return }
            detectedChatLanguage = detected
        }
    }

    func enableChatTranslation() {
        guard let chatId = openedChatId else { return }
        isChatTranslationEnabled = true
        TelegramChatTranslationPreferences.setEnabled(true, chatId: chatId)
        for message in messages.orderedMessageIds.compactMap({ messages.messages[$0] }) {
            ensureTranslation(for: message)
        }
    }

    func disableChatTranslation() {
        guard let chatId = openedChatId else { return }
        isChatTranslationEnabled = false
        TelegramChatTranslationPreferences.setEnabled(false, chatId: chatId)
        translationShownMessageIds.removeAll()
    }

    func dismissChatTranslationSuggestion() {
        guard let chatId = openedChatId else { return }
        TelegramChatTranslationPreferences.dismiss(chatId: chatId)
        detectedChatLanguage = nil
    }

    // MARK: Private

    private func senderKey(for message: Message) -> MacMessageSenderKey {
        switch message.senderId {
        case .messageSenderUser(let sender): .user(sender.userId)
        case .messageSenderChat(let sender): .chat(sender.chatId)
        }
    }
}
