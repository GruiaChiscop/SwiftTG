// CallControlsView.swift

import SwiftUI

// MARK: - CallControlsView

struct CallControlsView: View {
    let session: TelegramCallSession
    let isCompact: Bool
    let showConferenceMessages: () -> Void
    let endCall: () -> Void

    @Binding var showsConferenceEndConfirmation: Bool
    @Binding var showsConferenceLeaveConfirmation: Bool

    var body: some View {
        let controlsLayout = isCompact
            ? AnyLayout(VStackLayout(spacing: 20))
            : AnyLayout(HStackLayout(spacing: 0))

        controlsLayout {
            if session.isLocalVideoEnabled, !session.isScreenSharing {
                CallControlButton(
                    systemImage: "arrow.triangle.2.circlepath.camera",
                    label: "Flip",
                    showsLabel: !isCompact,
                    action: session.flipCamera,
                )
                .frame(maxWidth: isCompact ? nil : .infinity)
            } else {
                CallAudioRouteControl(
                    routes: session.availableAudioRoutes,
                    selectedRoute: session.selectedAudioRoute,
                    showsLabel: !isCompact,
                    select: session.selectAudioRoute,
                )
                .frame(maxWidth: isCompact ? nil : .infinity)
            }

            CallControlButton(
                systemImage: session.isScreenSharing ? "rectangle.on.rectangle.slash" : "video.fill",
                label: session.isScreenSharing ? "Stop Sharing" : "Video",
                isActive: session.isLocalVideoEnabled,
                isEnabled: session.canToggleVideo,
                showsLabel: !isCompact,
                action: session.toggleVideo,
            )
            .frame(maxWidth: isCompact ? nil : .infinity)

            if session.shouldShowConferenceRaiseHandControl {
                CallControlButton(
                    systemImage: "hand.raised.fill",
                    label: "Raise Hand",
                    isActive: session.isConferenceHandRaised,
                    isEnabled: session.canRaiseConferenceHand,
                    showsLabel: !isCompact,
                    action: session.raiseConferenceHand,
                )
                .frame(maxWidth: isCompact ? nil : .infinity)
            } else {
                CallControlButton(
                    systemImage: session.isMuted ? "mic.slash.fill" : "mic.fill",
                    label: "Mute",
                    isActive: session.isMuted,
                    isEnabled: session.canToggleMute,
                    showsLabel: !isCompact,
                    action: session.toggleMute,
                )
                .frame(maxWidth: isCompact ? nil : .infinity)
            }

            if session.showsConferenceCallUI, session.areConferenceMessagesAvailable {
                CallControlButton(
                    systemImage: "message.fill",
                    label: "Message",
                    showsLabel: !isCompact,
                    action: showConferenceMessages,
                )
                .frame(maxWidth: isCompact ? nil : .infinity)
            }

            CallControlButton(
                systemImage: "phone.down.fill",
                label: "End",
                isDestructive: true,
                showsLabel: !isCompact,
                action: endCall,
            )
            .frame(maxWidth: isCompact ? nil : .infinity)
        }
        .frame(maxWidth: isCompact ? nil : 420)
        .confirmationDialog(
            "Are you sure you want to leave this voice chat?",
            isPresented: $showsConferenceLeaveConfirmation,
            titleVisibility: .visible,
        ) {
            Button("End Voice Chat", role: .destructive) {
                showsConferenceEndConfirmation = true
            }
            Button("Leave Voice Chat", action: session.end)
            Button("Cancel", role: .cancel) {}
        }
        .alert("End voice chat", isPresented: $showsConferenceEndConfirmation) {
            Button("End", role: .destructive, action: session.endConferenceForEveryone)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to end this voice chat?")
        }
    }
}
