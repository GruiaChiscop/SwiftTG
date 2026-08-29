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
            if !isVideoExpanded {
                VStack(spacing: 4) {
                    Text("Group Call")
                        .font(.title.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text(connectionStatus ?? participantCountDescription)
                        .foregroundStyle(.secondary)
                }

                ConferenceEncryptionKeyView(emojis: verificationEmojis)
            }

            if localVideoView != nil || !videos.isEmpty {
                ConferenceVideoGrid(
                    localVideoView: localVideoView,
                    isLocalScreenSharing: isLocalScreenSharing,
                    videos: videos,
                    participants: participants,
                    performingParticipantActionId: performingParticipantActionId,
                    setExpanded: updateVideoExpansion,
                    setUIHidden: setUIHidden,
                    setCentralVideo: setCentralVideo,
                    setParticipantMuted: setParticipantMuted,
                    setParticipantVolume: setParticipantVolume,
                    openParticipantConversation: openParticipantConversation,
                    removeParticipant: removeParticipant,
                    requestVideoView: requestVideoView,
                )
                .frame(maxHeight: isVideoExpanded ? .infinity : nil)
            }

            if !isVideoExpanded {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(participants) { participant in
                            ConferenceParticipantRow(
                                participant: participant,
                                isPerformingAction: performingParticipantActionId == participant.id,
                                setMuted: { action in
                                    setParticipantMuted(participant, action)
                                },
                                setVolume: { volumeLevel, synchronize in
                                    setParticipantVolume(participant, volumeLevel, synchronize)
                                },
                                openConversation: {
                                    openParticipantConversation(participant)
                                },
                                cancelSpeakRequest: cancelSpeakRequest,
                                remove: {
                                    removeParticipant(participant)
                                },
                            )
                            .onAppear {
                                if participant.id == participants.last?.id {
                                    loadMoreParticipants()
                                }
                            }
                            Divider()
                                .padding(.leading, 64)
                        }

                        ConferenceInviteActionsView(
                            inviteLink: inviteLink,
                            isInvitingParticipant: isInvitingParticipant,
                            inviteParticipant: inviteParticipant,
                        )
                    }
                }
                .background(.white.opacity(0.1), in: .rect(cornerRadius: 20))
            }
        }
    }

    // MARK: Private

    @State private var isVideoExpanded = false

    private var participantCountDescription: String {
        participantCount == 1 ? "1 participant" : "\(participantCount) participants"
    }

    private func updateVideoExpansion(_ isExpanded: Bool) {
        isVideoExpanded = isExpanded
    }
}
