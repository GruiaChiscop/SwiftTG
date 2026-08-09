// MacPinnedMessagesView.swift

import SwiftUI
import TDLibKit

struct MacPinnedMessagesView: View {
    // MARK: Internal

    @Bindable var model: MacSessionModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Pinned Messages")
                    .font(.headline)
                Spacer()
                Button("Done", action: dismiss.callAsFunction)
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            if model.isLoadingPinnedMessages, model.pinnedMessages.isEmpty {
                ProgressView("Loading pinned messages…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = model.pinnedMessagesError, model.pinnedMessages.isEmpty {
                ContentUnavailableView(
                    "Pinned Messages Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error),
                )
            } else if model.pinnedMessages.isEmpty {
                ContentUnavailableView(
                    "No Pinned Messages",
                    systemImage: "pin",
                    description: Text("Pinned messages will appear here."),
                )
            } else {
                List(model.pinnedMessages, id: \.id) { message in
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
                    .buttonStyle(.plain)
                    // Without this, a `List` row built from multiple `Text` views reads as an
                    // empty cell to VoiceOver on macOS.
                    .accessibilityElement(children: .combine)
                }
                .listStyle(.plain)
            }
        }
        .frame(minWidth: 440, minHeight: 420)
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    private func open(_ message: Message) {
        guard let chatId = model.openedChatId else { return }
        dismiss()
        Task { @MainActor in
            await Task.yield()
            model.activateChat(chatId, messageId: message.id)
        }
    }
}
