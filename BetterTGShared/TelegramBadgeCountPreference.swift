// TelegramBadgeCountPreference.swift

import Combine
import Foundation

// MARK: - TelegramBadgeCountStyle

/// Matches Telegram-iOS's own Settings > Notifications > "Badge Counter" choice: the Home Screen
/// badge can show either the number of unread *chats* or the number of unread *messages*, both
/// excluding muted chats. `stylePublisher` lets `TDLib.startTdLibUpdateHandler()` react to the
/// user changing this immediately, using whichever of TDLib's two live counters was already
/// current - not a value cached from before some earlier app-lifecycle gap (see
/// `feedback_dont_reassert_stale_cache_as_correction` for why that distinction matters).
enum TelegramBadgeCountStyle: String, CaseIterable, Identifiable {
    case chats
    case messages

    // MARK: Internal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chats: "Chats"
        case .messages: "Messages"
        }
    }
}

// MARK: - TelegramBadgeCountPreference

@MainActor enum TelegramBadgeCountPreference {
    // MARK: Internal

    static var style: TelegramBadgeCountStyle {
        get { styleSubject.value }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: styleKey)
            styleSubject.send(newValue)
        }
    }

    static var stylePublisher: AnyPublisher<TelegramBadgeCountStyle, Never> {
        styleSubject.eraseToAnyPublisher()
    }

    // MARK: Private

    private static let styleKey = "TelegramBadgeCountPreference.style"

    private static let styleSubject = CurrentValueSubject<TelegramBadgeCountStyle, Never>(
        UserDefaults.standard.string(forKey: styleKey).flatMap(TelegramBadgeCountStyle.init) ?? .messages,
    )
}
