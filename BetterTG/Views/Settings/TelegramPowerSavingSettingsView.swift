// TelegramPowerSavingSettingsView.swift

import SwiftUI

struct TelegramPowerSavingSettingsView: View {
    var body: some View {
        Form {
            Section {
                Slider(value: thresholdBinding, in: 0...100, step: 5)
                    .accessibilityLabel("Power Saving Threshold")
                    .accessibilityValue(statusText)
            } footer: {
                Text(
                    "\(statusText). When active, Power Saving stops sticker animations from playing automatically in chats.",
                )
            }
        }
        .navigationTitle("Power Saving")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Private

    @AppStorage(TelegramPowerSavingSettings.thresholdDefaultsKey) private var threshold = 20

    private var thresholdBinding: Binding<Double> {
        Binding(
            get: { Double(threshold) },
            set: { newValue in
                threshold = Int(newValue)
                TelegramPowerSavingMonitor.shared.refresh()
            },
        )
    }

    private var statusText: String {
        switch threshold {
        case 0: "Always Off"
        case 100: "Always On"
        default: "When Below \(threshold)%"
        }
    }
}
