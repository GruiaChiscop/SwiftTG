// ConferenceParticipantRow.swift

import SwiftUI
@preconcurrency import TDLibKit

// MARK: - ConferenceParticipantRow

struct ConferenceParticipantRow: View {
    // MARK: Lifecycle

    init(participant: GroupCallParticipant, isSpeaking: Bool, isLocalMuted: Bool) {
        self.participant = participant
        self.isSpeaking = isSpeaking
        self.isLocalMuted = isLocalMuted
        self.invitedUserId = nil
    }

    init(invitedUserId: Int64) {
        self.participant = nil
        self.isSpeaking = false
        self.isLocalMuted = false
        self.invitedUserId = invitedUserId
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
                if isSpeaking {
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

    private let participant: GroupCallParticipant?
    private let isSpeaking: Bool
    private let isLocalMuted: Bool
    private let invitedUserId: Int64?
    private let service: any TelegramService = TDLib.shared.service

    private var userId: Int64? {
        if let invitedUserId {
            return invitedUserId
        }
        guard let participant, case .messageSenderUser(let sender) = participant.participantId else { return nil }
        return sender.userId
    }

    private var chatId: Int64? {
        guard let participant, case .messageSenderChat(let sender) = participant.participantId else { return nil }
        return sender.chatId
    }

    private var profileIdentity: String {
        if let userId {
            return "user-\(userId)"
        }
        if let chatId {
            return "chat-\(chatId)"
        }
        return "unknown"
    }

    private var displayTitle: String {
        if let user {
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

    private var isMuted: Bool {
        guard let participant else { return false }
        if participant.isCurrentUser {
            return isLocalMuted
        }
        return participant.isMutedForAllUsers || participant.isMutedForCurrentUser
    }

    private var statusDescription: String {
        guard invitedUserId == nil, let participant else { return "Invited" }
        if participant.isCurrentUser {
            return "You"
        }
        if isSpeaking {
            return "Speaking"
        }
        if participant.isHandRaised {
            return "Hand raised"
        }
        if isMuted {
            return "Muted"
        }
        return participant.bio.isEmpty ? "Listening" : participant.bio
    }

    private var statusSystemImage: String {
        if invitedUserId != nil {
            return "person.crop.circle.badge.clock"
        }
        if isSpeaking {
            return "mic.fill"
        }
        if participant?.isHandRaised == true {
            return "hand.raised.fill"
        }
        if isMuted {
            return "mic.slash.fill"
        }
        return "mic.fill"
    }

    private var statusColor: Color {
        if isSpeaking {
            return .green
        }
        if participant?.isHandRaised == true {
            return .orange
        }
        if isMuted {
            return .red
        }
        return .secondary
    }

    @MainActor private func loadProfile() async {
        user = nil
        chat = nil
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
