// ChatVM+ChatTranslation.swift

import SwiftUI
@preconcurrency import TDLibKit

extension ChatVM {
    var showsChatTranslationBanner: Bool {
        !isChatTranslationEnabled
            && detectedChatLanguage != nil
            && !TelegramChatTranslationPreferences.isDismissed(chatId: customChat.chat.id)
    }

    /// Called once the initial message page has rendered, so there's an actual sample to detect
    /// from - mirrors Telegram-iOS's own chat-language detection running against recently loaded
    /// history rather than a single message.
    @MainActor func refreshDetectedChatLanguage() {
        let sample = messages.map(\.message)
        let targetLanguageCode = telegramTranslationTargetLanguageCode()
        Task.background {
            guard let detected = telegramDetectedChatLanguage(from: sample), detected != targetLanguageCode
            else { return }
            await main { self.detectedChatLanguage = detected }
        }
    }

    @MainActor func enableChatTranslation() {
        isChatTranslationEnabled = true
        TelegramChatTranslationPreferences.setEnabled(true, chatId: customChat.chat.id)
        for customMessage in messages {
            ensureMessageTranslated(customMessage)
        }
    }

    @MainActor func disableChatTranslation() {
        isChatTranslationEnabled = false
        TelegramChatTranslationPreferences.setEnabled(false, chatId: customChat.chat.id)
        for customMessage in messages where customMessage.showsTranslation {
            customMessage.showsTranslation = false
        }
    }

    @MainActor func dismissChatTranslationSuggestion() {
        TelegramChatTranslationPreferences.dismiss(chatId: customChat.chat.id)
        detectedChatLanguage = nil
    }

    /// The shared "fetch, cache, show" primitive behind both the per-message Translate action and
    /// whole-chat translation - a no-op if already showing or already in flight.
    @MainActor func ensureMessageTranslated(_ customMessage: CustomMessage) {
        guard !customMessage.isTranslating, !customMessage.showsTranslation else { return }
        if customMessage.translatedText != nil {
            withAnimation { customMessage.showsTranslation = true }
            return
        }
        guard telegramMessageFormattedText(customMessage.message) != nil else { return }

        customMessage.isTranslating = true
        let chatId = customChat.chat.id
        let messageId = customMessage.id
        let targetLanguageCode = telegramTranslationTargetLanguageCode()
        Task.background {
            do {
                let translatedText = try await self.service.translateMessageText(
                    chatId: chatId,
                    messageId: messageId,
                    toLanguageCode: targetLanguageCode,
                    tone: nil,
                )
                await main {
                    customMessage.translatedText = translatedText
                    customMessage.isTranslating = false
                    withAnimation { customMessage.showsTranslation = true }
                }
            } catch {
                guard !Task.isCancelled else { return }
                await main {
                    customMessage.isTranslating = false
                    self.messageActionError = "Message couldn't be translated: \(telegramErrorDescription(error))"
                }
            }
        }
    }
}
