// TelegramInAppNotificationPreferences.swift

import Foundation

/// Controls for the in-app banner shown while the app is active (see `RootVM`'s
/// `handleNotificationGroupUpdate`/`presentInAppNotification` on iOS and the mirrored macOS
/// `MacSessionModel` path), distinct from TDLib's own per-scope notification settings - these only
/// affect how *that banner* behaves, not push notifications delivered while backgrounded.
enum TelegramInAppNotificationPreferences {
    // MARK: Internal

    static var soundEnabled: Bool {
        get { UserDefaults.standard.object(forKey: soundKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: soundKey) }
    }

    static var previewsEnabled: Bool {
        get { UserDefaults.standard.object(forKey: previewsKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: previewsKey) }
    }

    #if os(iOS)
    static var vibrateEnabled: Bool {
        get { UserDefaults.standard.object(forKey: vibrateKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: vibrateKey) }
    }
    #endif

    // MARK: Private

    private static let soundKey = "TelegramInAppNotificationPreferences.soundEnabled"
    private static let previewsKey = "TelegramInAppNotificationPreferences.previewsEnabled"
    #if os(iOS)
    private static let vibrateKey = "TelegramInAppNotificationPreferences.vibrateEnabled"
    #endif
}
