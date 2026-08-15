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

            if !session.encryptionEmojis.isEmpty {
                VStack(spacing: 8) {
                    Text(session.encryptionEmojis.joined(separator: " "))
                        .font(.title)
                    Text("Compare these emoji with the other person to verify this call is secure.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .accessibilityElement(children: .combine)
            }

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

                CallAudioRouteControl(
                    routes: session.availableAudioRoutes,
                    selectedRoute: session.selectedAudioRoute,
                ) { route in
                    session.selectAudioRoute(route)
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
        if session.engineState == .reconnecting {
            Text("Reconnecting…")
        } else if session.engineState == .failed {
            Text("Call Failed")
        } else if let connectedAt = session.connectedAt {
            TimelineView(.periodic(from: connectedAt, by: 1)) { context in
                Text(telegramClockDuration(Int(context.date.timeIntervalSince(connectedAt))))
            }
        } else {
            Text(pendingStatusText)
        }
    }
}

// MARK: - CallAudioRouteControl

private struct CallAudioRouteControl: View {
    // MARK: Internal

    let routes: [TelegramCallSession.AudioRoute]
    let selectedRoute: TelegramCallSession.AudioRoute
    let select: (TelegramCallSession.AudioRoute) -> Void

    var body: some View {
        Menu {
            ForEach(routes) { route in
                Button {
                    select(route)
                } label: {
                    Label(
                        route.name,
                        systemImage: route == selectedRoute ? "checkmark" : Self.systemImage(for: route.kind),
                    )
                }
            }
        } label: {
            Image(systemName: Self.systemImage(for: selectedRoute.kind))
                .font(.title2)
                .frame(width: 64, height: 64)
                .background(selectedRoute.kind == .speaker ? Color.accentColor : Color.gray.opacity(0.3), in: .circle)
                .foregroundStyle(selectedRoute.kind == .speaker ? .white : Color.primary)
        }
        .accessibilityLabel("Audio, \(selectedRoute.name)")
    }

    // MARK: Private

    private static func systemImage(for kind: TelegramCallSession.AudioRoute.Kind) -> String {
        switch kind {
        case .builtIn:
            "iphone"
        case .speaker:
            "speaker.wave.2.fill"
        case .wired:
            "headphones"
        case .bluetooth:
            "wave.3.right"
        case .external:
            "airplayaudio"
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
