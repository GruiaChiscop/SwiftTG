// ConferenceParticipantListView.swift

import SwiftUI

// MARK: - ConferenceParticipantListView

struct ConferenceParticipantListView: View {
    let participants: [ConferenceParticipantPresentation]
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

    var body: some View {
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
