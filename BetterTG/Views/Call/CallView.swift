// CallView.swift

import SwiftUI
import TDLibKit
import UIKit

// MARK: - CallView

/// Presented full-screen per `TelegramCallSession.shared.shouldShowCallView` (mounted from
/// `RootView`, matching `TelegramAudioPlayerBar`'s always-available-from-anywhere placement) - not
/// simply whenever a call exists, since an unanswered incoming call must leave the system's own
/// native CallKit incoming-call screen as the sole answer surface (see the doc comment on
/// `shouldShowCallView`).
struct CallView: View {
    // MARK: Internal

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // AVKit uses this full-screen view only as the transition source. The independent
            // sample-buffer renderer lives in its dedicated video-call content controller.
            if let pictureInPictureSourceView = session.pictureInPictureSourceView {
                CallVideoSurfaceView(videoView: pictureInPictureSourceView)
                    .id(ObjectIdentifier(pictureInPictureSourceView))
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
            }

            if let primaryVideoView {
                CallVideoSurfaceView(videoView: primaryVideoView)
                    .id(ObjectIdentifier(primaryVideoView))
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
            } else {
                CallBackground(userId: session.activeCall?.userId)
            }

            if primaryVideoView != nil {
                LinearGradient(
                    colors: [.black.opacity(0.4), .clear, .black.opacity(0.5)],
                    startPoint: .top,
                    endPoint: .bottom,
                )
                .ignoresSafeArea()
                .accessibilityHidden(true)
            }

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

                if primaryVideoView == nil {
                    CallPeerAvatar(user: user, fallbackTitle: displayName, userId: session.activeCall?.userId)
                        .frame(width: 128, height: 128)
                        .overlay {
                            Circle()
                                .stroke(.white.opacity(0.2), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
                }

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

                    CallWeakSignalView(
                        isVisible: session.connectedAt != nil
                            && session.engineState == .connected
                            && session.signalBars == 0,
                    )
                }
                .padding(.horizontal)

                if !session.encryptionEmojis.isEmpty {
                    CallEncryptionKeyView(
                        emojis: session.encryptionEmojis,
                        peerName: peerShortName,
                    )
                    .padding(.top)
                }

                Spacer()

                CallNoticeView(
                    isLocalMuted: session.isMuted,
                    isLocalVideoEnabled: session.isLocalVideoEnabled,
                    remoteAudioState: session.remoteAudioState,
                    remoteVideoState: session.remoteVideoState,
                    remoteBatteryLevel: session.remoteBatteryLevel,
                    peerName: peerShortName,
                )
                .padding(.bottom, 12)

                HStack {
                    if session.isLocalVideoEnabled {
                        CallControlButton(
                            systemImage: "arrow.triangle.2.circlepath.camera",
                            label: "Flip",
                            action: session.flipCamera,
                        )
                        .frame(maxWidth: .infinity)
                    } else {
                        CallAudioRouteControl(
                            routes: session.availableAudioRoutes,
                            selectedRoute: session.selectedAudioRoute,
                            select: session.selectAudioRoute,
                        )
                        .frame(maxWidth: .infinity)
                    }

                    CallControlButton(
                        systemImage: "video.fill",
                        label: "Video",
                        isActive: session.isLocalVideoEnabled,
                        isEnabled: session.canToggleVideo,
                        action: session.toggleVideo,
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

            if let secondaryVideoView {
                Button(action: swapPrimaryVideo) {
                    CallVideoSurfaceView(videoView: secondaryVideoView)
                        .id(ObjectIdentifier(secondaryVideoView))
                        .frame(width: 108, height: 152)
                        .clipShape(.rect(cornerRadius: 16))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(.white.opacity(0.25), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
                }
                .buttonStyle(.plain)
                .padding(.top, 72)
                .padding(.trailing, 16)
                .accessibilityLabel(secondaryVideoAccessibilityLabel)
            }
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled()
        .alert("Camera Access Required", isPresented: $session.showsCameraPermissionAlert) {
            Button("Open Settings", action: openSettings)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Allow camera access in Settings to use video during calls.")
        }
        .sheet(isPresented: cameraPreviewPresentation) {
            CallCameraPreviewView()
        }
        .task(id: session.activeCall?.userId) {
            user = nil
            isLocalVideoPrimary = false
            guard let userId = session.activeCall?.userId else { return }
            guard let loadedUser = try? await TDLib.shared.service.getUser(userId: userId) else { return }
            guard !Task.isCancelled else { return }
            user = loadedUser
        }
        .onChange(of: session.isLocalVideoEnabled) { _, isEnabled in
            if !isEnabled {
                isLocalVideoPrimary = false
            }
        }
    }

    // MARK: Private

    @Environment(\.openURL) private var openURL
    @State private var isLocalVideoPrimary = false
    @State private var user: User?
    @State private var session = TelegramCallSession.shared

    private var cameraPreviewPresentation: Binding<Bool> {
        Binding(
            get: { session.showsCameraPreview },
            set: { isPresented in
                if !isPresented {
                    session.cancelCameraPreview()
                }
            },
        )
    }

    private var primaryVideoView: UIView? {
        if isLocalVideoPrimary,
           session.isLocalVideoEnabled,
           let localVideoView = session.localVideoView
        {
            return localVideoView
        }
        if session.remoteVideoState != .inactive, let remoteVideoView = session.remoteVideoView {
            return remoteVideoView
        }
        if session.isLocalVideoEnabled, let localVideoView = session.localVideoView {
            return localVideoView
        }
        return nil
    }

    private var secondaryVideoView: UIView? {
        guard session.isLocalVideoEnabled,
              let localVideoView = session.localVideoView,
              session.remoteVideoState != .inactive,
              let remoteVideoView = session.remoteVideoView
        else { return nil }
        return isLocalVideoPrimary ? remoteVideoView : localVideoView
    }

    private var secondaryVideoAccessibilityLabel: String {
        isLocalVideoPrimary
            ? "Show \(peerShortName)'s video full screen"
            : "Show your video full screen"
    }

    private var displayName: String {
        guard let user else { return "Telegram" }
        let name = [user.firstName, user.lastName].filter { !$0.isEmpty }.joined(separator: " ")
        return name.isEmpty ? "Telegram" : name
    }

    private var peerShortName: String {
        guard let user else { return "The other person" }
        return user.firstName.isEmpty ? displayName : user.firstName
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }

    private func swapPrimaryVideo() {
        guard secondaryVideoView != nil else { return }
        isLocalVideoPrimary.toggle()
    }
}
