// CallView.swift

import SwiftUI
import TDLibKit

// MARK: - CallView

/// Presented full-screen per `TelegramCallSession.shared.shouldShowCallView` (mounted from
/// `RootView`, matching `TelegramAudioPlayerBar`'s always-available-from-anywhere placement) - not
/// simply whenever a call exists, since an unanswered incoming call must leave the system's own
/// native CallKit incoming-call screen as the sole answer surface (see the doc comment on
/// `shouldShowCallView`).
struct CallView: View {
    // MARK: Internal

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 8) {
                Text(displayName ?? "Telegram")
                    .font(.title.bold())
                statusView
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            Spacer()

            HStack(spacing: 40) {
                CallControlButton(
                    systemImage: session.isMuted ? "mic.slash.fill" : "mic.fill",
                    label: session.isMuted ? "Unmute" : "Mute",
                    isActive: session.isMuted,
                ) {
                    session.toggleMute()
                }

                CallControlButton(
                    systemImage: "phone.down.fill",
                    label: "End Call",
                    tint: .red,
                ) {
                    session.end()
                }

                CallControlButton(
                    systemImage: session.isSpeakerOn ? "speaker.wave.2.fill" : "speaker.fill",
                    label: session.isSpeakerOn ? "Speaker Off" : "Speaker On",
                    isActive: session.isSpeakerOn,
                ) {
                    session.toggleSpeaker()
                }
            }

            Spacer()
        }
        .padding(.bottom, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.thinMaterial)
        .task(id: session.activeCall?.userId) {
            displayName = nil
            guard let userId = session.activeCall?.userId else { return }
            guard let user = try? await TDLib.shared.service.getUser(userId: userId) else { return }
            let name = [user.firstName, user.lastName].filter { !$0.isEmpty }.joined(separator: " ")
            displayName = name.isEmpty ? nil : name
        }
    }

    // MARK: Private

    @State private var displayName: String?

    private let session = TelegramCallSession.shared

    private var pendingStatusText: String {
        guard let call = session.activeCall else { return "" }
        switch call.state {
        case .callStatePending:
            return call.isOutgoing ? "Calling…" : "Incoming Call"
        case .callStateExchangingKeys, .callStateReady:
            return "Connecting…"
        case .callStateHangingUp:
            return "Ending…"
        case .callStateDiscarded, .callStateError:
            return "Call Ended"
        }
    }

    @ViewBuilder private var statusView: some View {
        if let connectedAt = session.connectedAt {
            TimelineView(.periodic(from: connectedAt, by: 1)) { context in
                Text(telegramClockDuration(Int(context.date.timeIntervalSince(connectedAt))))
            }
        } else {
            Text(pendingStatusText)
        }
    }
}

// MARK: - CallControlButton

private struct CallControlButton: View {
    let systemImage: String
    let label: String
    var isActive = false
    var tint = Color.primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title2)
                .frame(width: 64, height: 64)
                .background(isActive ? Color.accentColor : Color.gray.opacity(0.3), in: .circle)
                .foregroundStyle(isActive ? .white : tint)
        }
        .accessibilityLabel(label)
    }
}
