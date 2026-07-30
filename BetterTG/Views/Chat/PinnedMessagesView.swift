// PinnedMessagesView.swift

import SwiftUI
import TDLibKit

struct PinnedMessagesView: View {
    // MARK: Internal

    var body: some View {
        NavigationStack {
            Group {
                if chatVM.isLoadingPinnedMessages, chatVM.pinnedMessages.isEmpty {
                    ProgressView("Loading pinned messages…")
                } else if let error = chatVM.pinnedMessagesError, chatVM.pinnedMessages.isEmpty {
                    ContentUnavailableView(
                        "Pinned Messages Unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error),
                    )
                } else if chatVM.pinnedMessages.isEmpty {
                    ContentUnavailableView(
                        "No Pinned Messages",
                        systemImage: "pin",
                        description: Text("Pinned messages will appear here."),
                    )
                } else {
                    List(chatVM.pinnedMessages, id: \.id) { message in
                        Button {
                            open(message)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(telegramMessageContentDescription(message))
                                    .foregroundStyle(.primary)
                                    .lineLimit(3)
                                Text(telegramMessageDateDescription(message.date))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Pinned Messages")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @Environment(ChatVM.self) private var chatVM

    private func open(_ message: Message) {
        dismiss()
        Task { @MainActor in
            await Task.yield()
            chatVM.navigateToMessage(id: message.id)
        }
    }
}
