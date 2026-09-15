// TelegramPowerSavingSettings.swift

import Foundation

/// 0 = Always Off, 100 = Always On, anything in between auto-activates once the battery drops to
/// or below that percentage - mirrors Telegram-iOS's own single-slider Power Saving model
/// (`PowerSaving.BatteryLevelLimit.*` strings) rather than a separate on/off toggle plus a
/// threshold.
enum TelegramPowerSavingSettings {
    static let thresholdDefaultsKey = "BetterTG.powerSaving.threshold"

    /// Defaults to 20 - a reasonable "low battery" cutoff, close to Telegram-iOS's own default of 15.
    static var threshold: Int {
        UserDefaults.standard.object(forKey: thresholdDefaultsKey) == nil
            ? 20
            : UserDefaults.standard.integer(forKey: thresholdDefaultsKey)
    }
}
