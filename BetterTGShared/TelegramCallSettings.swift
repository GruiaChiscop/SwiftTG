// TelegramCallSettings.swift

import Foundation

// MARK: - TelegramCallSettings

enum TelegramCallSettings {
    // MARK: Internal

    static let dataSavingDefaultsKey = "BetterTG.calls.dataSaving"
    static let useProxyForCallsDefaultsKey = "BetterTG.calls.useProxy"

    static var dataSaving: TelegramCallDataSaving {
        if let rawValue = UserDefaults.standard.string(forKey: dataSavingDefaultsKey),
           let value = TelegramCallDataSaving(rawValue: rawValue)
        {
            return value
        }
        return UserDefaults.standard.bool(forKey: legacyUseLessDataDefaultsKey) ? .always : .never
    }

    static var usesProxyForCalls: Bool {
        UserDefaults.standard.bool(forKey: useProxyForCallsDefaultsKey)
    }

    // MARK: Private

    private static let legacyUseLessDataDefaultsKey = "BetterTG.calls.useLessData"
}
