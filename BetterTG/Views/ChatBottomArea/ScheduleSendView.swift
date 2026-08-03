// ScheduleSendView.swift

import SwiftUI
import TDLibKit

/// Picking a date here immediately hands the chosen scheduling state to `onSchedule` and
/// dismisses - there's no separate "armed" state to confirm afterwards, matching Telegram's own
/// gesture. Used both to schedule a new send from the composer and to reschedule an already
/// -scheduled message from the Scheduled Messages screen.
struct ScheduleSendView: View {
    // MARK: Internal

    var title = "Schedule Message"
    /// Only offered for private chats, where TDLib can resolve "when the other user comes online";
    /// the caller is responsible for that check.
    var allowsSendWhenOnline: Bool
    var onSchedule: (MessageSchedulingState) -> Void

    var body: some View {
        NavigationStack {
            Form {
                if allowsSendWhenOnline {
                    Section {
                        Button("Send When Online") {
                            schedule(.messageSchedulingStateSendWhenOnline)
                        }
                    }
                }

                Section {
                    DatePicker(
                        "Send at",
                        selection: $sendDate,
                        in: Date()...Date().addingTimeInterval(Self.maximumScheduleInterval),
                        displayedComponents: [.date, .hourAndMinute],
                    )
                } footer: {
                    Text("The message will be sent at this time.")
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Schedule") {
                        schedule(.messageSchedulingStateSendAtDate(.init(
                            repeatPeriod: 0,
                            sendDate: Int(sendDate.timeIntervalSince1970),
                        )))
                    }
                }
            }
        }
    }

    // MARK: Private

    private static let maximumScheduleInterval: TimeInterval = 367 * 24 * 60 * 60

    @Environment(\.dismiss) private var dismiss
    @State private var sendDate = Date().addingTimeInterval(60 * 60)

    private func schedule(_ schedulingState: MessageSchedulingState) {
        dismiss()
        onSchedule(schedulingState)
    }
}
