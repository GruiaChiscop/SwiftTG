// TelegramChatTranslationPreferences.swift

import Foundation

/// Whether the user has turned whole-chat translation on, or dismissed the suggestion, for a given
/// chat - the only part of chat-wide translation that persists across launches. Which language a
/// chat was detected as, and the translations themselves, are not persisted; they're recomputed
/// from currently-loaded messages each time a chat opens.
enum TelegramChatTranslationPreferences {
    // MARK: Internal

    static func isEnabled(chatId: Int64) -> Bool {
        enabledChatIds.contains(chatId)
    }

    static func setEnabled(_ isEnabled: Bool, chatId: Int64) {
        var chatIds = enabledChatIds
        if isEnabled {
            chatIds.insert(chatId)
        } else {
            chatIds.remove(chatId)
        }
        enabledChatIds = chatIds
    }

    static func isDismissed(chatId: Int64) -> Bool {
        dismissedChatIds.contains(chatId)
    }

    static func dismiss(chatId: Int64) {
        dismissedChatIds.insert(chatId)
    }

    // MARK: Private

    private static let enabledChatIdsKey = "TelegramChatTranslationPreferences.enabledChatIds"
    private static let dismissedChatIdsKey = "TelegramChatTranslationPreferences.dismissedChatIds"

    private static var enabledChatIds: Set<Int64> {
        get { storedChatIds(forKey: enabledChatIdsKey) }
        set { setStoredChatIds(newValue, forKey: enabledChatIdsKey) }
    }

    private static var dismissedChatIds: Set<Int64> {
        get { storedChatIds(forKey: dismissedChatIdsKey) }
        set { setStoredChatIds(newValue, forKey: dismissedChatIdsKey) }
    }

    private static func storedChatIds(forKey key: String) -> Set<Int64> {
        Set((UserDefaults.standard.array(forKey: key) as? [Int64]) ?? [])
    }

    private static func setStoredChatIds(_ chatIds: Set<Int64>, forKey key: String) {
        UserDefaults.standard.set(Array(chatIds), forKey: key)
    }
}
