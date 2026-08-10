// TelegramScheduleSendView.swift

import SwiftUI
import TDLibKit

// MARK: - TelegramScheduleSendView

struct TelegramScheduleSendView: View {
    // MARK: Internal

    let allowsSendWhenOnline: Bool
    let onSchedule: (MessageSchedulingState) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Schedule Message")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            if allowsSendWhenOnline {
                Button("Send When Online") {
                    schedule(.messageSchedulingStateSendWhenOnline)
                }
            }

            DatePicker(
                "Send at",
                selection: $sendDate,
                in: Date.now...Date.now.addingTimeInterval(Self.maximumScheduleInterval),
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
        .padding()
        .frame(maxWidth: 440)
    }

    // MARK: Private

    private static let maximumScheduleInterval: TimeInterval = 367 * 24 * 60 * 60

    @Environment(\.dismiss) private var dismiss
    @State private var sendDate = Date.now.addingTimeInterval(60 * 60)

    private func schedule(_ state: MessageSchedulingState) {
        dismiss()
        onSchedule(state)
    }
}
