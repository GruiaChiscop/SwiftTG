// TelegramLanguageDetection.swift

import Foundation
import NaturalLanguage
import TDLibKit

/// On-device detection (no network round trip) of what language a piece of text is written in,
/// normalized to a code `translateMessageText` accepts - mirrors Telegram-iOS's own use of
/// `NLLanguageRecognizer` for translate eligibility (`Translate.swift`) and chat-language detection
/// (`ChatTranslation.swift`), just via TDLib instead of MTProto for the actual translation call.
func telegramDetectedLanguage(for text: String) -> String? {
    guard text.count >= 10 else { return nil }
    let recognizer = NLLanguageRecognizer()
    recognizer.processString(String(text.prefix(256)))
    defer { recognizer.reset() }
    guard let language = recognizer.dominantLanguage else { return nil }
    return normalizedTelegramTranslationLanguageCode(language.rawValue)
}

/// Samples up to the 20 most recent incoming messages with enough text to detect reliably, and
/// returns whichever detected language accounts for the most characters - mirrors
/// `ChatTranslation.swift`'s `chatTranslationState` sampling (same message count and per-message
/// length threshold), without its 1-hour result caching.
func telegramDetectedChatLanguage(from messages: [Message]) -> String? {
    var characterCountByLanguage = [String: Int]()
    var consideredCount = 0

    for message in messages.reversed() {
        guard consideredCount < 20 else { break }
        guard !message.isOutgoing,
              let text = telegramMessageFormattedText(message)?.text,
              text.count >= 10
        else { continue }
        guard let languageCode = telegramDetectedLanguage(for: text) else { continue }
        characterCountByLanguage[languageCode, default: 0] += text.count
        consideredCount += 1
    }

    return characterCountByLanguage.max(by: { $0.value < $1.value })?.key
}

private func normalizedTelegramTranslationLanguageCode(_ rawValue: String) -> String? {
    if telegramSupportedTranslationLanguageCodes.contains(rawValue) {
        return rawValue
    }
    let baseCode = String(rawValue.prefix(while: { $0 != "-" }))
    guard telegramSupportedTranslationLanguageCodes.contains(baseCode) else { return nil }
    return baseCode
}
