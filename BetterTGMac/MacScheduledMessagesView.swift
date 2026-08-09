// MacScheduledMessagesView.swift

import SwiftUI
import TDLibKit

struct MacScheduledMessagesView: View {
    // MARK: Internal

    @Bindable var model: MacSessionModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Scheduled Messages")
                    .font(.headline)
                Spacer()
                Button("Done", action: dismiss.callAsFunction)
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            if model.isLoadingScheduledMessages, model.scheduledMessages.isEmpty {
                ProgressView("Loading scheduled messages…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = model.scheduledMessagesError, model.scheduledMessages.isEmpty {
                ContentUnavailableView(
                    "Scheduled Messages Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error),
                )
            } else if model.scheduledMessages.isEmpty {
                ContentUnavailableView(
                    "No Scheduled Messages",
                    systemImage: "clock",
                    description: Text("Messages you schedule will appear here."),
                )
            } else {
                List(model.scheduledMessages, id: \.id) { message in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(telegramMessageContentDescription(message))
                            .foregroundStyle(.primary)
                            .lineLimit(3)
                        Text(telegramScheduledMessageTimeDescription(message.schedulingState))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                    // Without this, a `List` row built from multiple `Text` views reads as an
                    // empty cell to VoiceOver on macOS.
                    .accessibilityElement(children: .combine)
                    .contextMenu {
                        Button("Send Now", systemImage: "paperplane") {
                            model.sendScheduledMessageNow(message)
                        }
                        Button("Reschedule", systemImage: "clock") {
                            rescheduledMessage = message
                        }
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            model.deleteScheduledMessage(message)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .frame(minWidth: 440, minHeight: 420)
        .sheet(item: $rescheduledMessage) { message in
            MacScheduleSendView(
                title: "Reschedule Message",
                allowsSendWhenOnline: model.openedChat?.kind == .privateChat,
            ) { schedulingState in
                model.rescheduleMessage(message, to: schedulingState)
            }
        }
        .task { model.refreshScheduledMessages() }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var rescheduledMessage: Message?
}
