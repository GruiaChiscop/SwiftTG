// TelegramBlockedUsers.swift

import SwiftUI
import TDLibKit

// MARK: - TelegramBlockedSenderRow

private struct TelegramBlockedSenderRow: Identifiable {
    let sender: MessageSender
    let displayName: String

    var id: MessageSender { sender }
}

// MARK: - BlockedUsersView

struct BlockedUsersView: View {
    // MARK: Lifecycle

    init(service: any TelegramService) {
        self.service = service
    }

    // MARK: Internal

    var body: some View {
        Group {
            if isLoading, rows.isEmpty {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if rows.isEmpty {
                ContentUnavailableView(
                    "No Blocked Users",
                    systemImage: "hand.raised.slash",
                    description: Text("People and channels you block will appear here."),
                )
            } else {
                List(rows) { row in
                    HStack {
                        Circle()
                            .fill(Color(telegramAvatarId: row.sender.avatarId))
                            .overlay {
                                Text(String(row.displayName.prefix(1)).uppercased())
                                    .font(.headline)
                                    .foregroundStyle(.white)
                            }
                            .frame(width: 40, height: 40)
                            .accessibilityHidden(true)

                        Text(row.displayName)

                        Spacer()

                        Button("Unblock") {
                            Task { await unblock(row) }
                        }
                        .disabled(isUnblocking.contains(row.id))
                    }
                }
            }
        }
        .navigationTitle("Blocked Users")
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await loadBlockedSenders()
        }
        .alert("Couldn't Load Blocked Users", isPresented: errorIsPresented) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Private

    @State private var errorMessage: String?
    @State private var hasLoaded = false
    @State private var isLoading = false
    @State private var isUnblocking = Set<MessageSender>()
    @State private var rows = [TelegramBlockedSenderRow]()

    private let service: any TelegramService

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    errorMessage = nil
                }
            },
        )
    }

    @MainActor private func loadBlockedSenders() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let blocked = try await service.getBlockedMessageSenders(blockList: .blockListMain, limit: 100, offset: 0)
            var resolvedRows = [TelegramBlockedSenderRow]()
            for sender in blocked.senders {
                if let row = await resolvedRow(for: sender) {
                    resolvedRows.append(row)
                }
            }
            rows = resolvedRows
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }

    private func resolvedRow(for sender: MessageSender) async -> TelegramBlockedSenderRow? {
        switch sender {
        case .messageSenderUser(let value):
            guard let user = try? await service.getUser(userId: value.userId) else { return nil }
            return TelegramBlockedSenderRow(sender: sender, displayName: telegramUserDisplayName(user))
        case .messageSenderChat(let value):
            guard let chat = try? await service.getChat(chatId: value.chatId) else { return nil }
            return TelegramBlockedSenderRow(sender: sender, displayName: chat.title)
        }
    }

    @MainActor private func unblock(_ row: TelegramBlockedSenderRow) async {
        isUnblocking.insert(row.sender)
        defer { isUnblocking.remove(row.sender) }
        do {
            _ = try await service.setMessageSenderBlockList(blockList: nil, senderId: row.sender)
            rows.removeAll { $0.id == row.id }
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }
}

private extension MessageSender {
    var avatarId: Int64 {
        switch self {
        case .messageSenderUser(let value): value.userId
        case .messageSenderChat(let value): value.chatId
        }
    }
}
