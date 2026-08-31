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
                                    Image(systemName: "person.crop.circle.badge.plus")
                                        .resizable()
                                        .scaledToFit()
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
                .opacity(isConferenceUIHidden ? 0 : 1)
                .allowsHitTesting(!isConferenceUIHidden)
                .accessibilityHidden(isConferenceUIHidden)
                .frame(height: isConferenceUIHidden ? 0 : nil)

                Spacer(minLength: isConferenceUIHidden ? 0 : 24)

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
                        prefersTwoColumnLayout: usesSideConferenceControls,
                        setUIHidden: updateConferenceUIHidden,
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
            }
            .safeAreaPadding()
            .padding(.horizontal)
            .padding(.trailing, callControlsTrailingInset)
            .padding(.bottom, callControlsBottomInset)
            .accessibilityHidden(showsConferenceMessages)

            CallControlsView(
                session: session,
                isCompact: usesSideConferenceControls,
                showConferenceMessages: showConferenceMessages,
                endCall: endCall,
                showsConferenceEndConfirmation: $showsConferenceEndConfirmation,
                showsConferenceLeaveConfirmation: $showsConferenceLeaveConfirmation,
            )
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: usesSideConferenceControls ? .trailing : .bottom,
            )
            .safeAreaPadding()
            .padding(.horizontal)
            .opacity(isConferenceUIHidden ? 0 : 1)
            .allowsHitTesting(!isConferenceUIHidden)
            .accessibilityHidden(isConferenceUIHidden || showsConferenceMessages)

            if session.showsConferenceCallUI,
               !showsConferenceMessages,
               !isConferenceUIHidden,
               !session.conferenceMessages.isEmpty
            {
                VStack {
                    Spacer()

                    ConferenceMessageFeedView(messages: session.conferenceMessages)
                        .frame(maxWidth: 440, maxHeight: 180)

                    Color.clear
                        .frame(height: usesSideConferenceControls ? 0 : 116)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal)
                .padding(.trailing, usesSideConferenceControls ? 104 : 0)
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
            if let fallbackURL = session.conferenceInvitationFallbackURL {
                Button("Copy Invite Link") {
                    UIPasteboard.general.url = fallbackURL
                }
            }
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
        .onAppear(perform: callViewAppeared)
        .onDisappear(perform: callViewDisappeared)
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
            CallOrientationController.setAllowsLandscape(isVisible)
            if !isVisible {
                showsConferenceMessages = false
                isConferenceUIHidden = false
            }
        }
    }

    // MARK: Private

    @Environment(\.openURL) private var openURL
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var idleTimerToken: UUID?
    @State private var isConferenceUIHidden = false
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

    private var usesSideConferenceControls: Bool {
        session.showsConferenceCallUI
            && verticalSizeClass == .compact
            && UIDevice.current.userInterfaceIdiom == .phone
    }

    private var conferenceIncomingVideoQualityBinding: Binding<ConferenceIncomingVideoQuality> {
        Binding(
            get: { session.conferenceIncomingVideoQuality },
            set: { quality in
                session.setConferenceIncomingVideoQuality(quality)
            },
        )
    }

    private var callControlsBottomInset: CGFloat {
        isConferenceUIHidden || usesSideConferenceControls ? 0 : 104
    }

    private var callControlsTrailingInset: CGFloat {
        isConferenceUIHidden || !usesSideConferenceControls ? 0 : 104
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

    private func callViewAppeared() {
        acquireIdleTimer()
        CallOrientationController.setAllowsLandscape(session.showsConferenceCallUI)
    }

    private func callViewDisappeared() {
        releaseIdleTimer()
        CallOrientationController.setAllowsLandscape(false)
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

    private func updateConferenceUIHidden(_ isHidden: Bool) {
        isConferenceUIHidden = isHidden
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
