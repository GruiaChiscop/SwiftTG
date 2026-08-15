// CallRemoteStatusView.swift

import SwiftUI

// MARK: - CallRemoteStatusView

struct CallRemoteStatusView: View {
    let audioState: TelegramCallEngine.RemoteAudioState
    let batteryLevel: TelegramCallEngine.RemoteBatteryLevel

    var body: some View {
        if audioState == .muted || batteryLevel == .low {
            HStack(spacing: 12) {
                if audioState == .muted {
                    Label("Muted", systemImage: "mic.slash.fill")
                }
                if batteryLevel == .low {
                    Label("Low Battery", systemImage: "battery.25")
                }
            }
            .font(.footnote)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: .capsule)
        }
    }
}
