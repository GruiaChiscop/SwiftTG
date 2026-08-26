// ConferenceParticipantRow.swift

import SwiftUI
@preconcurrency import TDLibKit

// MARK: - ConferenceParticipantRow

struct ConferenceParticipantRow: View {
    // MARK: Lifecycle

    init(participant: ConferenceParticipantPresentation) {
        self.participant = participant
    }

    // MARK: Internal

    var body: some View {
        HStack(spacing: 12) {
            ProfileImageView(
                photo: profilePhoto,
                minithumbnail: profileMinithumbnail,
                title: displayTitle,
                userId: avatarId,
            )
            .frame(width: 44, height: 44)
            .overlay {
                if participant.isSpeaking {
                    Circle()
                        .stroke(.green, lineWidth: 2)
                }
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(displayTitle)
                    .font(.body.bold())
                    .lineLimit(1)
                Text(statusDescription)
                    .font(.subheadline)
                    .foregroundStyle(statusColor)
            }

            Spacer()

            Image(systemName: statusSystemImage)
                .foregroundStyle(statusColor)
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .task(id: profileIdentity) {
            await loadProfile()
        }
    }

    // MARK: Private

    @State private var chat: Chat?
    @State private var user: User?

    private let participant: ConferenceParticipantPresentation

    private var userId: Int64? { participant.userId }
    private var chatId: Int64? { participant.chatId }

    private var profileIdentity: String {
        participant.id
    }

    private var displayTitle: String {
        if let title = participant.title {
            return title
        } else if let user {
            return telegramUserDisplayName(user)
        }
        if let chat {
            return chat.title
        }
        return "Participant"
    }

    private var avatarId: Int64 { userId ?? chatId ?? 0 }
    private var profilePhoto: File? { user?.profilePhoto?.small ?? chat?.photo?.small }
    private var profileMinithumbnail: Minithumbnail? {
        user?.profilePhoto?.minithumbnail ?? chat?.photo?.minithumbnail
    }

    private var statusDescription: String { participant.subtitle }

    private var statusSystemImage: String {
        if participant.isInvited {
            return "person.crop.circle.badge.clock"
        }
        if participant.isSpeaking {
            return "mic.fill"
        }
        if participant.isHandRaised {
            return "hand.raised.fill"
        }
        if participant.isMuted {
            return "mic.slash.fill"
        }
        return "mic.fill"
    }

    private var statusColor: Color {
        if participant.isSpeaking {
            return .green
        }
        if participant.isHandRaised {
            return .orange
        }
        if participant.isMuted {
            return .red
        }
        return .secondary
    }

    @MainActor private func loadProfile() async {
        user = nil
        chat = nil
        guard participant.title == nil else { return }
        let service = TDLib.shared.service
        do {
            if let userId {
                let loadedUser = try await service.getUser(userId: userId)
                try Task.checkCancellation()
                user = loadedUser
            } else if let chatId {
                let loadedChat = try await service.getChat(chatId: chatId)
                try Task.checkCancellation()
                chat = loadedChat
            }
        } catch is CancellationError {
            return
        } catch {
            log("[GroupCall] couldn't load participant profile \(profileIdentity): \(error)")
        }
    }
}
