// TelegramPowerSavingMonitor.swift

import Observation
import UIKit

/// Tracks whether Power Saving should currently be active, combining the user's chosen threshold
/// (`TelegramPowerSavingSettings.threshold`) with the live battery level. Consumers (currently
/// just `TelegramStickerView`'s sticker-animation gate) read `isActive` directly - as an
/// `@Observable`, referencing it from a SwiftUI view body re-renders that view automatically when
/// either the battery level or the threshold changes.
@MainActor @Observable final class TelegramPowerSavingMonitor {
    // MARK: Lifecycle

    private init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        refresh()
        NotificationCenter.default.addObserver(
            forName: UIDevice.batteryLevelDidChangeNotification,
            object: nil,
            queue: .main,
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    // MARK: Internal

    static let shared = TelegramPowerSavingMonitor()

    private(set) var isActive = false

    /// Call after the threshold setting changes - nothing else notifies this monitor when
    /// `UserDefaults` changes underneath it.
    func refresh() {
        let threshold = TelegramPowerSavingSettings.threshold
        let level = UIDevice.current.batteryLevel
        // -1 means monitoring is unsupported/unavailable (e.g. the Simulator) - treat that as "not
        // low" rather than as 0%, which would otherwise force Power Saving on everywhere it runs.
        let batteryPercent = level < 0 ? 100 : Int((level * 100).rounded())
        isActive = switch threshold {
        case 0: false
        case 100: true
        default: batteryPercent <= threshold
        }
    }
}
