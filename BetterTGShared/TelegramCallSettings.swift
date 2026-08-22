// TelegramCallSettings.swift

import Foundation

// MARK: - TelegramCallSettings

enum TelegramCallSettings {
    static let useLessDataDefaultsKey = "BetterTG.calls.useLessData"
    static let useProxyForCallsDefaultsKey = "BetterTG.calls.useProxy"

    static var usesLessData: Bool {
        UserDefaults.standard.bool(forKey: useLessDataDefaultsKey)
    }

    static var usesProxyForCalls: Bool {
        UserDefaults.standard.bool(forKey: useProxyForCallsDefaultsKey)
    }
}
