// ConferenceInviteActionsView.swift

import SwiftUI

// MARK: - ConferenceInviteActionsView

/// Matches Telegram-iOS's trailing conference-list actions: add one member or share the invite link.
struct ConferenceInviteActionsView: View {
    let inviteLink: URL?
    let isInvitingParticipant: Bool
    let inviteParticipant: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: inviteParticipant) {
                HStack(spacing: 12) {
                    if isInvitingParticipant {
                        ProgressView()
                            .accessibilityHidden(true)
                    } else {
                        Image(systemName: "person.badge.plus")
                            .accessibilityHidden(true)
                    }
                    Text(isInvitingParticipant ? "Adding Member" : "Add Member")
                    Spacer()
                }
                .frame(minHeight: 52)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .disabled(isInvitingParticipant)

            if let inviteLink {
                Divider()
                    .padding(.leading, 50)

                ShareLink(item: inviteLink) {
                    Label("Share Invite Link", systemImage: "link")
                        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            }
        }
        .padding(.horizontal, 12)
    }
}
