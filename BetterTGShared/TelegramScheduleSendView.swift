// TelegramScheduleSendView.swift

import SwiftUI
import TDLibKit

// MARK: - TelegramMessageRepeatPeriod

enum TelegramMessageRepeatPeriod: Int, CaseIterable, Identifiable {
    case never = 0
    case daily = 86400
    case weekly = 604_800
    case everyTwoWeeks = 1_209_600
    case monthly = 2_592_000
    case everyThreeMonths = 7_862_400
    case everySixMonths = 15_724_800
    case yearly = 31_536_000

    // MARK: Internal

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .never: "Never"
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .everyTwoWeeks: "Every Two Weeks"
        case .monthly: "Monthly"
        case .everyThreeMonths: "Every Three Months"
        case .everySixMonths: "Every Six Months"
        case .yearly: "Yearly"
        }
    }
}

// MARK: - TelegramScheduleSendView

struct TelegramScheduleSendView: View {
    // MARK: Internal

    let allowsSendWhenOnline: Bool
    var allowsRepeat = false
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

            if allowsRepeat {
                Picker("Repeat", selection: $repeatPeriod) {
                    ForEach(TelegramMessageRepeatPeriod.allCases) { period in
                        Text(period.title).tag(period)
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Schedule") {
                    schedule(.messageSchedulingStateSendAtDate(.init(
                        repeatPeriod: repeatPeriod.rawValue,
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
    @State private var repeatPeriod = TelegramMessageRepeatPeriod.never

    private func schedule(_ state: MessageSchedulingState) {
        dismiss()
        onSchedule(state)
    }
}
