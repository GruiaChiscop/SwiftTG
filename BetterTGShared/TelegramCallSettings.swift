// TelegramCallSettings.swift

import Foundation

// MARK: - TelegramCallSettings

enum TelegramCallSettings {
    static let useLessDataDefaultsKey = "BetterTG.calls.useLessData"

    static var usesLessData: Bool {
        UserDefaults.standard.bool(forKey: useLessDataDefaultsKey)
    }
}
