// TelegramSendAsPicker.swift

import SwiftUI
@preconcurrency import TDLibKit

// MARK: - TelegramSendAsCandidates

/// The identities a user may send messages in a chat as, when there is more than one.
struct TelegramSendAsCandidates: Identifiable {
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
                    select(row.sender)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: row.isChannel ? "megaphone.fill" : "person.crop.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                            .frame(width: 32)
                            .accessibilityHidden(true)
                        Text(row.title)
                        Spacer()
                        if row.isCurrent {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                                .accessibilityHidden(true)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
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
                    isChannel: false,
                    isCurrent: currentSender == sender,
                )
            case .messageSenderChat(let value):
                guard let chat = try? await service.getChat(chatId: value.chatId) else { return nil }
                return Row(
                    sender: sender,
                    title: chat.title,
                    isChannel: true,
                    isCurrent: currentSender == sender,
                )
            }
        }
    }

    private func select(_ sender: MessageSender) {
        onSelect(sender)
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
