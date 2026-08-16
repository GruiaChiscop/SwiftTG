// CallNoticeView.swift

import SwiftUI
import UIKit

// MARK: - CallNoticeView

struct CallNoticeView: View {
    // MARK: Internal

    let isLocalMuted: Bool
    let isLocalVideoEnabled: Bool
    let remoteAudioState: TelegramCallEngine.RemoteAudioState
    let remoteVideoState: TelegramCallEngine.RemoteVideoState
    let remoteBatteryLevel: TelegramCallEngine.RemoteBatteryLevel
    let peerName: String

    var body: some View {
        Group {
            if isLocalMuted
                || remoteAudioState == .muted
                || remoteBatteryLevel == .low
                || (remoteVideoState != .inactive && !isLocalVideoEnabled)
            {
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

                    if remoteVideoState != .inactive, !isLocalVideoEnabled {
                        CallNoticeLabel(
                            title: "Your camera is off",
                            systemImage: "video.slash.fill",
                        )
                    }
                }
            }
        }
        .task(id: remoteAudioState) {
            await announceRemoteAudioChange()
        }
        .task(id: remoteVideoState) {
            await announceRemoteVideoChange()
        }
        .task(id: remoteBatteryLevel) {
            await announceRemoteBatteryChange()
        }
    }

    // MARK: Private

    @State private var observedRemoteAudioState: TelegramCallEngine.RemoteAudioState?
    @State private var observedRemoteVideoState: TelegramCallEngine.RemoteVideoState?
    @State private var observedRemoteBatteryLevel: TelegramCallEngine.RemoteBatteryLevel?

    private func announceRemoteAudioChange() async {
        let current = remoteAudioState
        let isInitialValue = observedRemoteAudioState == nil
        guard observedRemoteAudioState != current else { return }
        observedRemoteAudioState = current

        guard !isInitialValue || current != .active else { return }

        let state = current == .muted ? "off" : "on"
        await postAnnouncement("\(peerName)'s microphone is \(state)")
    }

    private func announceRemoteBatteryChange() async {
        let current = remoteBatteryLevel
        guard observedRemoteBatteryLevel != current else { return }
        observedRemoteBatteryLevel = current

        guard current == .low else { return }
        await postAnnouncement("\(peerName)'s battery is low")
    }

    private func announceRemoteVideoChange() async {
        let current = remoteVideoState
        let isInitialValue = observedRemoteVideoState == nil
        guard observedRemoteVideoState != current else { return }
        observedRemoteVideoState = current

        guard !isInitialValue || current != .inactive else { return }

        let state =
            switch current {
            case .inactive: "off"
            case .active: "on"
            case .paused: "paused"
            }
        await postAnnouncement("\(peerName)'s camera is \(state)")
    }

    private func postAnnouncement(_ announcement: String) async {
        do {
            try await Task.sleep(for: .milliseconds(300))
        } catch {
            return
        }

        guard !Task.isCancelled else { return }
        UIAccessibility.post(notification: .announcement, argument: announcement)
    }
}
