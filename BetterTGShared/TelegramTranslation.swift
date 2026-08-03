// TelegramTranslation.swift

import Foundation
import TDLibKit

/// Codes `translateText`/`translateMessageText` accept for `toLanguageCode`, per TDLib's own
/// documentation on those methods.
let telegramSupportedTranslationLanguageCodes = Set<String>([
    "af", "sq", "am", "ar", "hy", "az", "eu", "be", "bn", "bs", "bg", "ca", "ceb", "zh-CN", "zh",
    "zh-Hans", "zh-TW", "zh-Hant", "co", "hr", "cs", "da", "nl", "en", "eo", "et", "fi", "fr", "fy",
    "gl", "ka", "de", "el", "gu", "ht", "ha", "haw", "he", "iw", "hi", "hmn", "hu", "is", "ig", "id",
    "in", "ga", "it", "ja", "jv", "kn", "kk", "km", "rw", "ko", "ku", "ky", "lo", "la", "lv", "lt",
    "lb", "mk", "mg", "ms", "ml", "mt", "mi", "mr", "mn", "my", "ne", "no", "ny", "or", "ps", "fa",
    "pl", "pt", "pt-BR", "pa", "ro", "ru", "sm", "gd", "sr", "st", "sn", "sd", "si", "sk", "sl",
    "so", "es", "su", "sw", "sv", "tl", "tg", "ta", "tt", "te", "th", "tr", "tk", "uk", "ur", "ug",
    "uz", "vi", "cy", "xh", "yi", "ji", "yo", "zu",
])

/// Most of TDLib's supported codes are plain ISO 639-1, matching `Locale`'s own language code
/// directly - falls back to English when the device's language isn't one TDLib translates to.
func telegramTranslationTargetLanguageCode(locale: Locale = .current) -> String {
    guard let languageCode = locale.language.languageCode?.identifier,
          telegramSupportedTranslationLanguageCodes.contains(languageCode)
    else { return "en" }
    return languageCode
}

/// Matches TDLib's own restriction ("must not be used in secret chats"), the same non-empty
/// text/caption check the message context menu's "Copy" action already uses, and - mirroring
/// Telegram-iOS's own per-message translate eligibility (`Translate.swift`'s `canTranslateText`) -
/// doesn't offer translation for text that's already in the target language.
func telegramMessageCanBeTranslated(
    _ message: Message,
    chatType: ChatType?,
    targetLanguageCode: String = telegramTranslationTargetLanguageCode(),
) -> Bool {
    if case .chatTypeSecret = chatType {
        return false
    }
    guard let formattedText = telegramMessageFormattedText(message) else { return false }
    if let detectedLanguageCode = telegramDetectedLanguage(for: formattedText.text),
       detectedLanguageCode == targetLanguageCode
    {
        return false
    }
    return true
}
