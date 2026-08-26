// ConferenceParticipantsView.swift

import SwiftUI

// MARK: - ConferenceParticipantsView

/// The list portion of Telegram-iOS's conference screen. Video tiles and participant actions are
/// intentionally separate follow-up layers; this view owns only participant identity and status.
struct ConferenceParticipantsView: View {
    // MARK: Internal

    let participants: [ConferenceParticipantPresentation]
    let participantCount: Int
    let connectionStatus: String?

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text("Group Call")
                    .font(.title.bold())
                    .accessibilityAddTraits(.isHeader)
                Text(connectionStatus ?? participantCountDescription)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(participants) { participant in
                        ConferenceParticipantRow(participant: participant)
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
