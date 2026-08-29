// CallView.swift

import AVFoundation
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

                    if session.showsConferenceCallUI {
                        Menu("More", systemImage: "ellipsis") {
                            if session.conferenceHasIncomingVideo {
                                Menu("Incoming Video Quality", systemImage: "gearshape") {
                                    Picker(
                                        "Incoming Video Quality",
                                        selection: conferenceIncomingVideoQualityBinding,
                                    ) {
                                        ForEach(ConferenceIncomingVideoQuality.allCases) { quality in
                                            Text(quality.title)
                                                .tag(quality)
                                        }
                                    }
                                }
                            }

                            if #available(iOS 15.0, *), session.canToggleMute {
                                Button("Microphone Modes", systemImage: "waveform") {
                                    AVCaptureDevice.showSystemUserInterface(.microphoneModes)
                                }
                            }
                        }
                        .labelStyle(.iconOnly)
                        .font(.title3.bold())
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: .circle)
                    } else {
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
                        setParticipantVolume: session.setConferenceParticipantVolume,
                        openParticipantConversation: session.openConferenceParticipantConversation,
                        cancelSpeakRequest: session.cancelConferenceSpeakRequest,
                        removeParticipant: session.removeConferenceParticipant,
                        loadMoreParticipants: session.loadMoreConferenceParticipants,
                        setCentralVideo: session.setConferenceCentralVideo,
                        requestVideoView: session.requestConferenceVideoView,
                    )
                    .frame(maxHeight: .infinity)
                    .padding(.bottom, 12)
                } else {
                    if primaryVideoView == nil {
                        if session.isScreenSharing {
                            VStack(spacing: 12) {
                                Image(systemName: "rectangle.on.rectangle")
                                    .font(.system(size: 42, weight: .medium))
                                    .accessibilityHidden(true)
                                Text("You are sharing your screen")
                                    .font(.headline)
                            }
                            .padding(24)
                            .background(.ultraThinMaterial, in: .rect(cornerRadius: 20))
                        } else {
                            CallPeerAvatar(user: user, fallbackTitle: displayName, userId: session.activeCall?.userId)
                                .frame(width: 128, height: 128)
                                .overlay {
                                    Circle()
                                        .stroke(.white.opacity(0.2), lineWidth: 1)
                                }
                                .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
                        }
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

                    if session.shouldShowConferenceRaiseHandControl {
                        CallControlButton(
                            systemImage: "hand.raised.fill",
                            label: "Raise Hand",
                            isActive: session.isConferenceHandRaised,
                            isEnabled: session.canRaiseConferenceHand,
                            action: session.raiseConferenceHand,
                        )
                        .frame(maxWidth: .infinity)
                    } else {
                        CallControlButton(
                            systemImage: session.isMuted ? "mic.slash.fill" : "mic.fill",
                            label: "Mute",
                            isActive: session.isMuted,
                            isEnabled: session.canToggleMute,
                            action: session.toggleMute,
                        )
                        .frame(maxWidth: .infinity)
                    }

                    if session.showsConferenceCallUI, session.areConferenceMessagesAvailable {
                        CallControlButton(
                            systemImage: "message.fill",
                            label: "Message",
                            action: showConferenceMessages,
                        )
                        .frame(maxWidth: .infinity)
                    }

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
            .accessibilityHidden(showsConferenceMessages)

            if session.showsConferenceCallUI,
               !showsConferenceMessages,
               !session.conferenceMessages.isEmpty
            {
                VStack {
                    Spacer()

                    ConferenceMessageFeedView(messages: session.conferenceMessages)
                        .frame(maxWidth: 440, maxHeight: 180)

                    Color.clear
                        .frame(height: 116)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal)
                .allowsHitTesting(false)
            }

            if session.showsConferenceCallUI, showsConferenceMessages {
                Button(action: hideConferenceMessages) {
                    Color.black
                        .opacity(0.4)
                        .ignoresSafeArea()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close messages")

                ConferenceMessagesView(
                    messages: session.conferenceMessages,
                    canSend: session.canSendConferenceMessages,
                    characterLimit: session.conferenceMessageCharacterLimit,
                    send: { message in
                        await session.sendConferenceMessage(message)
                    },
                    dismiss: hideConferenceMessages,
                )
                .frame(maxWidth: 440, maxHeight: .infinity)
                .padding(.horizontal)
                .padding(.top, 64)
                .padding(.bottom, 24)
            }

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
        .alert("Couldn't Invite Participant", isPresented: $session.showsConferenceInvitationError) {
            Button("OK") {}
        } message: {
            Text(session.conferenceInvitationErrorMessage)
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
        .onChange(of: session.showsConferenceCallUI) { _, isVisible in
            if !isVisible {
                showsConferenceMessages = false
            }
        }
    }

    // MARK: Private

    @Environment(\.openURL) private var openURL
    @State private var idleTimerToken: UUID?
    @State private var isLocalVideoPrimary = false
    @State private var showsConferenceEndConfirmation = false
    @State private var showsConferenceLeaveConfirmation = false
    @State private var showsConferenceMessages = false
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

    private var conferenceIncomingVideoQualityBinding: Binding<ConferenceIncomingVideoQuality> {
        Binding(
            get: { session.conferenceIncomingVideoQuality },
            set: { quality in
                session.setConferenceIncomingVideoQuality(quality)
            },
        )
    }

    private var primaryVideoView: UIView? {
        if isLocalVideoPrimary,
           session.isLocalVideoEnabled,
           !session.isScreenSharing,
           let localVideoView = session.localVideoView
        {
            return localVideoView
        }
        if session.remoteVideoState != .inactive, let remoteVideoView = session.remoteVideoView {
            return remoteVideoView
        }
        if session.isLocalVideoEnabled,
           !session.isScreenSharing,
           let localVideoView = session.localVideoView
        {
            return localVideoView
        }
        return nil
    }

    private var secondaryVideoView: UIView? {
        guard session.isLocalVideoEnabled,
              !session.isScreenSharing,
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

    private func showConferenceMessages() {
        showsConferenceMessages = true
    }

    private func hideConferenceMessages() {
        showsConferenceMessages = false
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
