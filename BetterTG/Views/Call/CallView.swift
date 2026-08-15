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
        ZStack {
            CallBackground(userId: session.activeCall?.userId)

            VStack {
                HStack {
                    Button("Minimize Call", systemImage: "chevron.down", action: session.minimizeCallView)
                        .labelStyle(.iconOnly)
                        .font(.title3.bold())
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: .circle)

                    Spacer()
                }

                Spacer(minLength: 24)

                CallPeerAvatar(user: user, fallbackTitle: displayName, userId: session.activeCall?.userId)
                    .frame(width: 128, height: 128)
                    .overlay {
                        Circle()
                            .stroke(.white.opacity(0.2), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.25), radius: 24, y: 12)

                VStack(spacing: 6) {
                    Text(displayName)
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                        .lineLimit(2)

                    CallStatusView(
                        call: session.activeCall,
                        connectedAt: session.connectedAt,
                        engineState: session.engineState,
                        signalBars: session.signalBars,
                    )
                    .font(.title3)
                    .foregroundStyle(.secondary)

                    CallRemoteStatusView(
                        audioState: session.remoteAudioState,
                        batteryLevel: session.remoteBatteryLevel,
                    )
                }
                .padding(.horizontal)

                if !session.encryptionEmojis.isEmpty {
                    CallEncryptionKeyView(emojis: session.encryptionEmojis)
                        .padding(.top)
                }

                Spacer()

                HStack {
                    CallAudioRouteControl(
                        routes: session.availableAudioRoutes,
                        selectedRoute: session.selectedAudioRoute,
                        select: session.selectAudioRoute,
                    )
                    .frame(maxWidth: .infinity)

                    CallControlButton(
                        systemImage: session.isMuted ? "mic.slash.fill" : "mic.fill",
                        label: "Mute",
                        isActive: session.isMuted,
                        action: session.toggleMute,
                    )
                    .frame(maxWidth: .infinity)

                    CallControlButton(
                        systemImage: "phone.down.fill",
                        label: "End",
                        isDestructive: true,
                        action: session.end,
                    )
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: 420)
            }
            .safeAreaPadding()
            .padding(.horizontal)
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled()
        .task(id: session.activeCall?.userId) {
            user = nil
            guard let userId = session.activeCall?.userId else { return }
            guard let loadedUser = try? await TDLib.shared.service.getUser(userId: userId) else { return }
            guard !Task.isCancelled else { return }
            user = loadedUser
        }
    }

    // MARK: Private

    @State private var user: User?

    private let session = TelegramCallSession.shared

    private var displayName: String {
        guard let user else { return "Telegram" }
        let name = [user.firstName, user.lastName].filter { !$0.isEmpty }.joined(separator: " ")
        return name.isEmpty ? "Telegram" : name
    }
}
