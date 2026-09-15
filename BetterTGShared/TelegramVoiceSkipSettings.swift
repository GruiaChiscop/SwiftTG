// TelegramVoiceSkipSettings.swift

import Foundation

/// How far Skip Forward/Backward move within a voice message, and how that's scaled down for
/// notes shorter than the configured amount so a single skip doesn't just overshoot straight to
/// an endpoint every time (matching the user's own observation of WhatsApp's behavior: a very
/// short note steps by 1 second instead of the normal amount).
enum TelegramVoiceSkipSettings {
    static let presets = [5, 10, 15, 30]

    static let defaultsKey = "BetterTG.voicePlayback.skipInterval"

    static var interval: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: defaultsKey)
            return presets.contains(stored) ? stored : 5
        }
        set {
            UserDefaults.standard.set(newValue, forKey: defaultsKey)
        }
    }

    /// The configured interval, unless the note is shorter than it - then falls back to 1 second
    /// so skipping still does something meaningful instead of always landing on an endpoint.
    static func effectiveStep(forDuration duration: Int) -> Int {
        duration < interval ? 1 : interval
    }
}
