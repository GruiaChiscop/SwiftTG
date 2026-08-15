// CallNoticeView.swift

import SwiftUI

// MARK: - CallNoticeView

struct CallNoticeView: View {
    let isLocalMuted: Bool
    let remoteAudioState: TelegramCallEngine.RemoteAudioState
    let remoteBatteryLevel: TelegramCallEngine.RemoteBatteryLevel
    let peerName: String

    var body: some View {
        if isLocalMuted || remoteAudioState == .muted || remoteBatteryLevel == .low {
            VStack(spacing: 8) {
                if isLocalMuted {
                    CallNoticeLabel(
                        title: "Your microphone is off",
                        systemImage: "mic.slash.fill",
                    )
                }

                if remoteAudioState == .muted {
                    CallNoticeLabel(
                        title: "\(peerName)'s microphone is off",
                        systemImage: "mic.slash.fill",
                    )
                }

                if remoteBatteryLevel == .low {
                    CallNoticeLabel(
                        title: "\(peerName)'s battery is low",
                        systemImage: "battery.25",
                    )
                }
            }
        }
    }
}
