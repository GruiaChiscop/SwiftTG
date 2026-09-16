// TelegramSendAsPicker.swift

import SwiftUI
@preconcurrency import TDLibKit

// MARK: - TelegramSendAsCandidates

/// The identities a user may send messages in a chat as, when there is more than one. Keeps
/// `needsPremium` alongside each sender - TDLib lists an identity as a "candidate" even when the
/// user can't actually use it without Telegram Premium (e.g. commenting as a channel you
/// administer in a group that channel isn't linked to); trying to send as one anyway fails server
/// -side with `SEND_AS_PEER_INVALID`, so the picker has to gate on this itself. Mirrors Unigram's
/// `ChatMessageSender.NeedsPremium` check in `DialogViewModel.SetSender`.
struct TelegramSendAsCandidates: Identifiable {
    let senders: [ChatMessageSender]

    var id: String {
        senders.map { sender in
            switch sender.sender {
            case .messageSenderUser(let value): "u\(value.userId)"
            case .messageSenderChat(let value): "c\(value.chatId)"
            }
        }
        .joined(separator: ",")
    }
}

// MARK: - TelegramSendAsPicker

struct TelegramSendAsPicker: View {
    // MARK: Internal

    let candidates: TelegramSendAsCandidates
    let currentSender: MessageSender?
    let service: any TelegramService
    let onSelect: (MessageSender) -> Void

    var body: some View {
        NavigationStack {
            List(rows) { row in
                Button {
                    select(row)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: row.isChannel ? "megaphone.fill" : "person.crop.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                            .frame(width: 32)
                            .accessibilityHidden(true)
                        Text(row.title)
                        Spacer()
                        if isLocked(row) {
                            Image(systemName: "lock.fill")
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                        if row.isCurrent {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                                .accessibilityHidden(true)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    isLocked(row) ? "\(row.title), Telegram Premium required" : row.title,
                )
                .accessibilityAddTraits(row.isCurrent ? [.isSelected] : [])
            }
            .overlay {
                if rows.isEmpty {
                    ProgressView("Loading…")
                }
            }
            .navigationTitle("Send As")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
                .alert("Telegram Premium", isPresented: $showsPremiumAlert) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(
                        "Subscribe to **Telegram Premium** to be able to comment on behalf of your channels in any group chat.",
                    )
                }
        }
        #if os(macOS)
        .frame(minWidth: 320, minHeight: 360)
        #endif
        .task { await load() }
    }

    // MARK: Private

    private struct Row: Identifiable {
        let sender: MessageSender
        let title: String
        let isChannel: Bool
        let isCurrent: Bool
        let needsPremium: Bool

        var id: String {
            switch sender {
            case .messageSenderUser(let value): "u\(value.userId)"
            case .messageSenderChat(let value): "c\(value.chatId)"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var rows = [Row]()
    @State private var isCurrentUserPremium = false
    @State private var showsPremiumAlert = false

    @MainActor private func load() async {
        async let premium = (try? service.getMe())?.isPremium == true
        rows = await candidates.senders.concurrentCompactMap { candidate in
            switch candidate.sender {
            case .messageSenderUser(let value):
                guard let user = try? await service.getUser(userId: value.userId) else { return nil }
                return Row(
                    sender: candidate.sender,
                    title: telegramUserDisplayName(user),
                    isChannel: false,
                    isCurrent: currentSender == candidate.sender,
                    needsPremium: candidate.needsPremium,
                )
            case .messageSenderChat(let value):
                guard let chat = try? await service.getChat(chatId: value.chatId) else { return nil }
                return Row(
                    sender: candidate.sender,
                    title: chat.title,
                    isChannel: true,
                    isCurrent: currentSender == candidate.sender,
                    needsPremium: candidate.needsPremium,
                )
            }
        }
        isCurrentUserPremium = await premium
    }

    private func isLocked(_ row: Row) -> Bool {
        row.needsPremium && !isCurrentUserPremium
    }

    private func select(_ row: Row) {
        guard !isLocked(row) else {
            showsPremiumAlert = true
            return
        }
        onSelect(row.sender)
        dismiss()
    }
}

// MARK: - telegramSendAsAccessibilityLabel

/// "Send As, <name>" for the collapsed avatar button - resolves the current identity's display
/// name the same way the picker's own rows do, so the label always matches what selecting it
/// would show.
func telegramSendAsAccessibilityLabel(
    for sender: MessageSender?,
    service: any TelegramService,
) async -> String {
    guard let sender else { return "Send As" }
    let name = await TelegramSenderName.displayName(service: service, senderId: sender)
    guard let name, !name.isEmpty else { return "Send As" }
    return "Send As, \(name)"
}
