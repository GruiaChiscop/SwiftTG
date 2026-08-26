// ConferenceParticipantsView.swift

import SwiftUI
import TDLibKit

// MARK: - ConferenceParticipantsView

/// The list portion of Telegram-iOS's conference screen. Video tiles and participant actions are
/// intentionally separate follow-up layers; this view owns only participant identity and status.
struct ConferenceParticipantsView: View {
    // MARK: Internal

    let participants: [GroupCallParticipant]
    let invitedUserIds: [Int64]
    let participantCount: Int
    let speakingParticipantIds: Set<MessageSender>
    let isLocalMuted: Bool

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text("Group Call")
                    .font(.title.bold())
                    .accessibilityAddTraits(.isHeader)
                Text(participantCountDescription)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(participants, id: \.participantId) { participant in
                        ConferenceParticipantRow(
                            participant: participant,
                            isSpeaking: speakingParticipantIds.contains(participant.participantId),
                            isLocalMuted: isLocalMuted,
                        )
                        Divider()
                            .padding(.leading, 64)
                    }

                    ForEach(invitedUserIds, id: \.self) { userId in
                        ConferenceParticipantRow(invitedUserId: userId)
                        Divider()
                            .padding(.leading, 64)
                    }
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
