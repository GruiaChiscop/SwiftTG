// ScheduledMessagesView.swift

import SwiftUI
import TDLibKit

struct ScheduledMessagesView: View {
    // MARK: Internal

    var body: some View {
        NavigationStack {
            Group {
                if chatVM.isLoadingScheduledMessages, chatVM.scheduledMessages.isEmpty {
                    ProgressView("Loading scheduled messages…")
                } else if chatVM.scheduledMessages.isEmpty {
                    ContentUnavailableView(
                        "No Scheduled Messages",
                        systemImage: "clock",
                        description: Text("Messages you schedule will appear here."),
                    )
                } else {
                    List(chatVM.scheduledMessages, id: \.id) { message in
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
                        .swipeActions(edge: .trailing) {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                chatVM.deleteScheduledMessage(message)
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button("Send Now", systemImage: "paperplane") {
                                chatVM.sendScheduledMessageNow(message)
                            }
                            .tint(.blue)
                            Button("Reschedule", systemImage: "clock") {
                                rescheduledMessage = message
                            }
                            .tint(.orange)
                        }
                        .contextMenu {
                            Button("Send Now", systemImage: "paperplane") {
                                chatVM.sendScheduledMessageNow(message)
                            }
                            Button("Reschedule", systemImage: "clock") {
                                rescheduledMessage = message
                            }
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                chatVM.deleteScheduledMessage(message)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Scheduled Messages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
            .alert(
                "Scheduled Messages Error",
                isPresented: Binding(
                    get: { chatVM.scheduledMessagesError != nil },
                    set: { isPresented in
                        if !isPresented {
                            chatVM.scheduledMessagesError = nil
                        }
                    },
                ),
            ) {
                Button("OK") {}
            } message: {
                Text(chatVM.scheduledMessagesError ?? "")
            }
            .sheet(item: $rescheduledMessage) { message in
                ScheduleSendView(title: "Reschedule Message", allowsSendWhenOnline: chatVM.customChat.user != nil) {
                    schedulingState in
                    chatVM.rescheduleMessage(message, to: schedulingState)
                }
            }
            .task { chatVM.refreshScheduledMessages() }
            .refreshable { chatVM.refreshScheduledMessages() }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @Environment(ChatVM.self) private var chatVM
    @State private var rescheduledMessage: Message?
}
