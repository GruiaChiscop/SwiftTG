// ConferenceParticipantsView.swift

import SwiftUI
import UIKit

// MARK: - ConferenceParticipantsView

/// The participant area of Telegram-iOS's conference screen, including requested remote video
/// endpoints and the audio-only participant list.
struct ConferenceParticipantsView: View {
    // MARK: Internal

    let participants: [ConferenceParticipantPresentation]
    let localVideoView: UIView?
    let isLocalScreenSharing: Bool
    let videos: [ConferenceVideoPresentation]
    let participantCount: Int
    let connectionStatus: String?
    let verificationEmojis: [String]
    let inviteLink: URL?
    let isInvitingParticipant: Bool
    let performingParticipantActionId: String?
    let inviteParticipant: () -> Void
    let setParticipantMuted: (ConferenceParticipantPresentation, ConferenceParticipantMuteAction) -> Void
    let setParticipantVolume: (ConferenceParticipantPresentation, Int, Bool) -> Void
    let openParticipantConversation: (ConferenceParticipantPresentation) -> Void
    let cancelSpeakRequest: () -> Void
    let removeParticipant: (ConferenceParticipantPresentation) -> Void
    let loadMoreParticipants: () -> Void
    let setUIHidden: (Bool) -> Void
    let setCentralVideo: (_ endpointId: String?, _ isExpanded: Bool) -> Void
    let requestVideoView: (String, @escaping @MainActor (UIView?) -> Void) -> Void

    var body: some View {
        VStack(spacing: 16) {
            if !isVideoUIHidden {
                VStack(spacing: 4) {
                    Text("Group Call")
                        .font(.title.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text(connectionStatus ?? participantCountDescription)
                        .foregroundStyle(.secondary)
                }

                ConferenceEncryptionKeyView(emojis: verificationEmojis)
            }

            GeometryReader { proxy in
                let usesTwoColumnLayout = proxy.size.width > 588 && hasVideo
                let participantColumnWidth = min(
                    horizontalSizeClass == .regular ? 356 : 340,
                    max(240, proxy.size.width - 354),
                )
                let hidesParticipantList = isVideoUIHidden || (!usesTwoColumnLayout && isVideoExpanded)
                let contentLayout = usesTwoColumnLayout
                    ? AnyLayout(HStackLayout(spacing: isVideoUIHidden ? 0 : 14))
                    : AnyLayout(VStackLayout(spacing: hasVideo && !hidesParticipantList ? 16 : 0))
                let videoGrid = ConferenceVideoGrid(
                    localVideoView: localVideoView,
                    isLocalScreenSharing: isLocalScreenSharing,
                    videos: videos,
                    participants: participants,
                    performingParticipantActionId: performingParticipantActionId,
                    setExpanded: updateVideoExpansion,
                    setUIHidden: updateVideoUIHidden,
                    setCentralVideo: setCentralVideo,
                    setParticipantMuted: setParticipantMuted,
                    setParticipantVolume: setParticipantVolume,
                    openParticipantConversation: openParticipantConversation,
                    removeParticipant: removeParticipant,
                    requestVideoView: requestVideoView,
                )
                let participantList = ConferenceParticipantListView(
                    participants: participants,
                    inviteLink: inviteLink,
                    isInvitingParticipant: isInvitingParticipant,
                    performingParticipantActionId: performingParticipantActionId,
                    inviteParticipant: inviteParticipant,
                    setParticipantMuted: setParticipantMuted,
                    setParticipantVolume: setParticipantVolume,
                    openParticipantConversation: openParticipantConversation,
                    cancelSpeakRequest: cancelSpeakRequest,
                    removeParticipant: removeParticipant,
                    loadMoreParticipants: loadMoreParticipants,
                )

                contentLayout {
                    videoGrid
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: usesTwoColumnLayout || isVideoExpanded ? .infinity : nil,
                        )
                        .frame(height: hasVideo ? nil : 0)
                        .opacity(hasVideo ? 1 : 0)
                        .allowsHitTesting(hasVideo)
                        .accessibilityHidden(!hasVideo)

                    participantList
                        .frame(width: usesTwoColumnLayout ? (hidesParticipantList ? 0 : participantColumnWidth) : nil)
                        .frame(height: !usesTwoColumnLayout && hidesParticipantList ? 0 : nil)
                        .opacity(hidesParticipantList ? 0 : 1)
                        .allowsHitTesting(!hidesParticipantList)
                        .accessibilityHidden(hidesParticipantList)
                }
            }
        }
    }

    // MARK: Private

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isVideoExpanded = false
    @State private var isVideoUIHidden = false

    private var hasVideo: Bool {
        localVideoView != nil || !videos.isEmpty
    }

    private var participantCountDescription: String {
        participantCount == 1 ? "1 participant" : "\(participantCount) participants"
    }

    private func updateVideoExpansion(_ isExpanded: Bool) {
        isVideoExpanded = isExpanded
    }

    private func updateVideoUIHidden(_ isHidden: Bool) {
        isVideoUIHidden = isHidden
        setUIHidden(isHidden)
    }
}
