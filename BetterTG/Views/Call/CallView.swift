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

            if session.showsConferenceCallUI {
                Color.black
                    .ignoresSafeArea()
            } else if let primaryVideoView {
                CallVideoSurfaceView(videoView: primaryVideoView)
                    .id(ObjectIdentifier(primaryVideoView))
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
            } else {
                CallBackground(userId: session.activeCall?.userId)
            }

            if !session.showsConferenceCallUI, primaryVideoView != nil {
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

                    if !session.showsConferenceCallUI {
                        if session.canAddConferenceParticipant {
                            Button(action: showConferenceParticipantPicker) {
                                Label {
                                    Text("Add Participant")
                                } icon: {
                                    Image("CallNavigationAddPerson")
                                        .resizable()
                                        .renderingMode(.template)
                                        .frame(width: 40, height: 40)
                                }
                                .labelStyle(.iconOnly)
                            }
                            .frame(width: 40, height: 40)
                            .background(.ultraThinMaterial, in: .circle)
                        } else if session.isUpgradingToConference {
                            ProgressView()
                                .frame(width: 40, height: 40)
                                .background(.ultraThinMaterial, in: .circle)
                                .accessibilityLabel("Preparing conference")
                        }
                    }
                }

                Spacer(minLength: 24)

                if session.showsConferenceCallUI {
                    ConferenceParticipantsView(
                        participants: session.conferenceParticipantPresentations,
                        localVideoView: session.localVideoView,
                        isLocalScreenSharing: session.isScreenSharing,
                        videos: session.conferenceVideoPresentations,
                        participantCount: session.conferenceParticipantCount,
                        connectionStatus: session.conferenceConnectionStatus,
                        verificationEmojis: session.conferenceVerificationEmojis,
                        inviteLink: session.conferenceInviteURL,
                        isInvitingParticipant: session.isInvitingConferenceParticipant,
                        performingParticipantActionId: session.conferenceParticipantActionId,
                        inviteParticipant: showConferenceParticipantPicker,
                        setParticipantMuted: session.setConferenceParticipantMuted,
                        removeParticipant: session.removeConferenceParticipant,
                        requestVideoView: session.requestConferenceVideoView,
                    )
                    .frame(maxHeight: .infinity)
                    .padding(.bottom, 12)
                } else {
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
                }

                HStack {
                    if session.isLocalVideoEnabled, !session.isScreenSharing {
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
                        systemImage: session.isScreenSharing ? "rectangle.on.rectangle.slash" : "video.fill",
                        label: session.isScreenSharing ? "Stop Sharing" : "Video",
                        isActive: session.isLocalVideoEnabled,
                        isEnabled: session.canToggleVideo,
                        action: session.toggleVideo,
                    )
                    .frame(maxWidth: .infinity)

                    CallControlButton(
                        systemImage: session.isMuted ? "mic.slash.fill" : "mic.fill",
                        label: "Mute",
                        isActive: session.isMuted,
                        isEnabled: session.canToggleMute,
                        action: session.toggleMute,
                    )
                    .frame(maxWidth: .infinity)

                    CallControlButton(
                        systemImage: "phone.down.fill",
                        label: "End",
                        isDestructive: true,
                        action: endCall,
                    )
                    .frame(maxWidth: .infinity)
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
                .frame(maxWidth: 420)
            }
            .safeAreaPadding()
            .padding(.horizontal)

            if !session.showsConferenceCallUI, let secondaryVideoView {
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
        .sheet(isPresented: $showsConferenceParticipantPicker) {
            NavigationStack {
                ConferenceParticipantPicker(excludedUserIds: session.excludedConferenceParticipantUserIds) {
                    userId, isVideo in
                    session.addConferenceParticipant(userId: userId, isVideo: isVideo)
                }
            }
            .preferredColorScheme(.dark)
        }
        .onAppear(perform: acquireIdleTimer)
        .onDisappear(perform: releaseIdleTimer)
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
    @State private var idleTimerToken: UUID?
    @State private var isLocalVideoPrimary = false
    @State private var showsConferenceEndConfirmation = false
    @State private var showsConferenceLeaveConfirmation = false
    @State private var showsConferenceParticipantPicker = false
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

    private func acquireIdleTimer() {
        guard idleTimerToken == nil else { return }
        idleTimerToken = ApplicationIdleTimer.acquire()
    }

    private func releaseIdleTimer() {
        guard let idleTimerToken else { return }
        ApplicationIdleTimer.release(idleTimerToken)
        self.idleTimerToken = nil
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }

    private func showConferenceParticipantPicker() {
        showsConferenceParticipantPicker = true
    }

    private func endCall() {
        if session.canEndConferenceForEveryone {
            showsConferenceLeaveConfirmation = true
        } else {
            session.end()
        }
    }

    private func swapPrimaryVideo() {
        guard secondaryVideoView != nil else { return }
        isLocalVideoPrimary.toggle()
    }
}
