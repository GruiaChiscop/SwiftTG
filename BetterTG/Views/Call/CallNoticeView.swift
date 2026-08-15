// CallNoticeView.swift

import SwiftUI

// MARK: - CallNoticeView

struct CallNoticeView: View {
    // MARK: Internal

    let isLocalMuted: Bool
    let remoteAudioState: TelegramCallEngine.RemoteAudioState
    let remoteBatteryLevel: TelegramCallEngine.RemoteBatteryLevel
    let peerName: String

    var body: some View {
        Group {
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
        .onChange(of: remoteAudioState, announceRemoteAudioChange)
        .onChange(of: remoteBatteryLevel, announceRemoteBatteryChange)
    }

    // MARK: Private

    private func announceRemoteAudioChange(
        previous _: TelegramCallEngine.RemoteAudioState,
        current: TelegramCallEngine.RemoteAudioState,
    ) {
        let state = current == .muted ? "off" : "on"
        AccessibilityNotification.Announcement("\(peerName)'s microphone is \(state)").post()
    }

    private func announceRemoteBatteryChange(
        previous _: TelegramCallEngine.RemoteBatteryLevel,
        current: TelegramCallEngine.RemoteBatteryLevel,
    ) {
        guard current == .low else { return }
        AccessibilityNotification.Announcement("\(peerName)'s battery is low").post()
    }
}
