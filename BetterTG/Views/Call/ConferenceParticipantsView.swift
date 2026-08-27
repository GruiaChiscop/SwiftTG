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
    let videos: [ConferenceVideoPresentation]
    let participantCount: Int
    let connectionStatus: String?
    let verificationEmojis: [String]
    let inviteLink: URL?
    let isInvitingParticipant: Bool
    let performingParticipantActionId: String?
    let inviteParticipant: () -> Void
    let setParticipantMuted: (ConferenceParticipantPresentation, ConferenceParticipantMuteAction) -> Void
    let removeParticipant: (ConferenceParticipantPresentation) -> Void
    let requestVideoView: (String, @escaping @MainActor (UIView?) -> Void) -> Void

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text("Group Call")
                    .font(.title.bold())
                    .accessibilityAddTraits(.isHeader)
                Text(connectionStatus ?? participantCountDescription)
                    .foregroundStyle(.secondary)
            }

            ConferenceEncryptionKeyView(emojis: verificationEmojis)

            if localVideoView != nil || !videos.isEmpty {
                ConferenceVideoGrid(
                    localVideoView: localVideoView,
                    videos: videos,
                    requestVideoView: requestVideoView,
                )
                .frame(height: 200)
            }

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(participants) { participant in
                        ConferenceParticipantRow(
                            participant: participant,
                            isPerformingAction: performingParticipantActionId == participant.id,
                            setMuted: { action in
                                setParticipantMuted(participant, action)
                            },
                            remove: {
                                removeParticipant(participant)
                            },
                        )
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

    // MARK: Private

    private var participantCountDescription: String {
        participantCount == 1 ? "1 participant" : "\(participantCount) participants"
    }
}
