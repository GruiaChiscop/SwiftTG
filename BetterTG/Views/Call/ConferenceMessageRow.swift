// ConferenceMessageRow.swift

import SwiftUI
@preconcurrency import TDLibKit

// MARK: - ConferenceMessageRow

struct ConferenceMessageRow: View {
    // MARK: Internal

    let message: ConferenceMessagePresentation

    var body: some View {
        HStack(spacing: 10) {
            ProfileImageView(
                photo: profilePhoto,
                minithumbnail: profileMinithumbnail,
                title: displayTitle,
                userId: avatarId,
            )
            .frame(width: 28, height: 28)
            .accessibilityHidden(true)

            Text(
                "\(Text(displayTitle).bold()) \(Text(getAttributedString(from: message.formattedText)))",
            )
            .font(.subheadline)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 4)
        .padding(.trailing, 13)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 18))
        .frame(maxWidth: 330)
        .accessibilityElement(children: .combine)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .task(id: profileIdentity) {
            await loadProfile()
        }
    }

    // MARK: Private

    @State private var chat: Chat?
    @State private var user: User?

    private var profileIdentity: String {
        if let userId = message.userId {
            return "user-\(userId)"
        }
        return "chat-\(message.chatId ?? 0)"
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

    private var avatarId: Int64 { message.userId ?? message.chatId ?? 0 }
    private var profilePhoto: File? { user?.profilePhoto?.small ?? chat?.photo?.small }
    private var profileMinithumbnail: Minithumbnail? {
        user?.profilePhoto?.minithumbnail ?? chat?.photo?.minithumbnail
    }

    @MainActor private func loadProfile() async {
        user = nil
        chat = nil
        do {
            if let userId = message.userId {
                let loadedUser = try await TDLib.shared.service.getUser(userId: userId)
                try Task.checkCancellation()
                user = loadedUser
            } else if let chatId = message.chatId {
                let loadedChat = try await TDLib.shared.service.getChat(chatId: chatId)
                try Task.checkCancellation()
                chat = loadedChat
            }
        } catch is CancellationError {
            return
        } catch {
            log("[GroupCall] couldn't load message sender \(profileIdentity): \(error)")
        }
    }
}
