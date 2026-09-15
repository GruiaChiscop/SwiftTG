// TelegramLockscreenNamePreference.swift

import Foundation

/// Whether the sender/chat name stays visible on the lock screen even while iOS's own system-wide
/// "Show Previews: When Unlocked" setting is hiding the message body - see
/// `AppDelegate.registerNotificationCategories()` (iOS app target), which reads this to decide
/// whether to register `.hiddenPreviewsShowTitle` for Telegram's push categories. Defaults to
/// `true`, matching WhatsApp's own always-on behavior.
enum TelegramLockscreenNamePreference {
    static let defaultsKey = "TelegramLockscreenNamePreference.isEnabled"

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }
}
