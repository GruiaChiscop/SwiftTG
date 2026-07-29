// TelegramMessageReactionsView.swift

import SwiftUI
import TDLibKit

struct TelegramMessageReactionsView: View {
    let reactions: [MessageReaction]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Reactions")
                .font(.callout)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
        .background(Color.secondary.opacity(0.14), in: Capsule())
        .accessibilityValue(telegramReactionDescription(reactions) ?? "")
    }
}

struct TelegramReactionDetailsView: View {
    let service: any TelegramService
    let chatId: Int64
    let messageId: Int64

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty, isLoading {
                    ProgressView("Loading reactions…")
                } else if entries.isEmpty, let errorMessage {
                    ContentUnavailableView(
                        "Couldn't Load Reactions",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage),
                    )
                } else {
                    List {
                        ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                            HStack {
                                Text(entry.senderName)
                                Spacer()
                                Text(telegramReactionSymbol(entry.reaction.type))
                                    .font(.title3)
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(entry.senderName), \(telegramReactionSymbol(entry.reaction.type))")
                            .onAppear {
                                guard index == entries.count - 1 else { return }
                                Task { await loadNextPage() }
                            }
                        }
                        if isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .navigationTitle("Reactions")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 320, minHeight: 260)
        .task { await loadNextPage() }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var entries = [ReactionEntry]()
    @State private var nextOffset: String? = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    private struct ReactionEntry {
        let reaction: AddedReaction
        let senderName: String
    }

    @MainActor
    private func loadNextPage() async {
        guard !isLoading, let offset = nextOffset else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let page = try await service.getMessageAddedReactions(
                chatId: chatId,
                limit: 100,
                messageId: messageId,
                offset: offset,
                reactionType: nil,
            )
            var newEntries = [ReactionEntry]()
            for reaction in page.reactions {
                let senderName: String
                if reaction.isOutgoing {
                    senderName = "You"
                } else {
                    senderName = await TelegramSenderName.displayName(
                        service: service,
                        senderId: reaction.senderId,
                    ) ?? "Unknown"
                }
                newEntries.append(ReactionEntry(reaction: reaction, senderName: senderName))
            }
            entries.append(contentsOf: newEntries)
            nextOffset = page.nextOffset.isEmpty ? nil : page.nextOffset
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
