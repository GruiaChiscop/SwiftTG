// MacScheduleSendView.swift

import SwiftUI
import TDLibKit

/// Picking a date here immediately hands the chosen scheduling state to `onSchedule` and
/// dismisses - there's no separate "armed" state to confirm afterwards, matching Telegram's own
/// gesture. Used both to schedule a new send from the composer and to reschedule an already
/// -scheduled message from the Scheduled Messages window.
struct MacScheduleSendView: View {
    // MARK: Internal

    var title = "Schedule Message"
    /// Only offered for private chats, where TDLib can resolve "when the other user comes online";
    /// the caller is responsible for that check.
    var allowsSendWhenOnline: Bool
    var onSchedule: (MessageSchedulingState) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.headline)

            if allowsSendWhenOnline {
                Button("Send When Online") {
                    schedule(.messageSchedulingStateSendWhenOnline)
                }
            }

            DatePicker(
                "Send at",
                selection: $sendDate,
                in: Date()...Date().addingTimeInterval(Self.maximumScheduleInterval),
                displayedComponents: [.date, .hourAndMinute],
            )

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Schedule") {
                    schedule(.messageSchedulingStateSendAtDate(.init(
                        repeatPeriod: 0,
                        sendDate: Int(sendDate.timeIntervalSince1970),
                    )))
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 340)
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
