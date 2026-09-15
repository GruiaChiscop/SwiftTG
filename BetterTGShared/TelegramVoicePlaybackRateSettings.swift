// TelegramVoicePlaybackRateSettings.swift

import Foundation

/// The last-chosen voice message playback speed, applied to every voice note played afterward
/// until changed again - matches Telegram-iOS's own persisted `voicePlaybackRate` behavior.
enum TelegramVoicePlaybackRateSettings {
    /// The presets a tap cycles through, in order. Telegram-iOS also offers 0.5x/4x/8x/16x via a
    /// long-press menu; this only wires the tap-cycle set.
    static let presets: [Float] = [1, 1.5, 2]

    static let defaultsKey = "BetterTG.voicePlayback.rate"

    static var rate: Float {
        get {
            let stored = UserDefaults.standard.float(forKey: defaultsKey)
            return presets.contains(stored) ? stored : 1
        }
        set {
            UserDefaults.standard.set(newValue, forKey: defaultsKey)
        }
    }

    static func next(after rate: Float) -> Float {
        guard let index = presets.firstIndex(of: rate) else { return presets[0] }
        return presets[(index + 1) % presets.count]
    }

    static func title(for rate: Float) -> String {
        rate == rate.rounded() ? "\(Int(rate))x" : String(format: "%.1fx", rate)
    }
}
