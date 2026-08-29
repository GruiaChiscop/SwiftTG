// VideoChatJoinAsPicker.swift

import SwiftUI
@preconcurrency import TDLibKit

// MARK: - VideoChatJoinCandidates

/// The identities a user may join a chat's video chat as, when there is more than one.
struct VideoChatJoinCandidates: Identifiable {
    let senders: [MessageSender]

    var id: String {
        senders.map { sender in
            switch sender {
            case .messageSenderUser(let value): "u\(value.userId)"
            case .messageSenderChat(let value): "c\(value.chatId)"
            }
        }
        .joined(separator: ",")
    }
}

// MARK: - VideoChatJoinAsPicker

struct VideoChatJoinAsPicker: View {
    // MARK: Internal

    let chatId: Int64
    let candidates: VideoChatJoinCandidates
    let service: any TelegramService
    let onSelect: (MessageSender) -> Void

    var body: some View {
        NavigationStack {
            List(rows) { row in
                Button {
                    select(row.sender)
                } label: {
                    HStack(spacing: 12) {
                        ProfileImageView(
                            photo: row.photo,
                            minithumbnail: row.minithumbnail,
                            title: row.title,
                            userId: row.colorSeed,
                        )
                        .frame(width: 44, height: 44)
                        .accessibilityHidden(true)

                        Text(row.title)
                        Spacer()
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            .overlay {
                if rows.isEmpty {
                    ProgressView("Loading…")
                }
            }
            .navigationTitle("Join As")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task { await load() }
    }

    // MARK: Private

    private struct Row: Identifiable {
        let sender: MessageSender
        let title: String
        let photo: File?
        let minithumbnail: Minithumbnail?
        /// Seed for the fallback avatar color - the user or chat id behind `sender`.
        let colorSeed: Int64

        var id: String {
            switch sender {
            case .messageSenderUser(let value): "u\(value.userId)"
            case .messageSenderChat(let value): "c\(value.chatId)"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var rows = [Row]()

    @MainActor private func load() async {
        rows = await candidates.senders.concurrentCompactMap { sender in
            switch sender {
            case .messageSenderUser(let value):
                guard let user = try? await service.getUser(userId: value.userId) else { return nil }
                return Row(
                    sender: sender,
                    title: telegramUserDisplayName(user),
                    photo: user.profilePhoto?.small,
                    minithumbnail: user.profilePhoto?.minithumbnail,
                    colorSeed: user.id,
                )
            case .messageSenderChat(let value):
                guard let chat = try? await service.getChat(chatId: value.chatId) else { return nil }
                return Row(
                    sender: sender,
                    title: chat.title,
                    photo: chat.photo?.small,
                    minithumbnail: chat.photo?.minithumbnail,
                    colorSeed: value.chatId,
                )
            }
        }
    }

    private func select(_ sender: MessageSender) {
        Task {
            _ = try? await service.setVideoChatDefaultParticipant(
                chatId: chatId,
                defaultParticipantId: sender,
            )
        }
        onSelect(sender)
        dismiss()
    }
}
