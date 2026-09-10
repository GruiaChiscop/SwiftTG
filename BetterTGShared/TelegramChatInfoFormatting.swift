// TelegramChatInfoFormatting.swift

import Foundation
import TDLibKit

func telegramNotificationScope(for type: ChatType) -> NotificationSettingsScope {
    switch type {
    case .chatTypePrivate, .chatTypeSecret:
        .notificationSettingsScopePrivateChats
    case .chatTypeBasicGroup:
        .notificationSettingsScopeGroupChats
    case .chatTypeSupergroup(let value):
        value.isChannel ? .notificationSettingsScopeChannelChats : .notificationSettingsScopeGroupChats
    }
}

/// `nil` for the default "all reactions" - only surfaced when a group/channel has narrowed or
/// disabled reactions, matching where Telegram itself shows it.
func telegramReactionsSummary(_ reactions: ChatAvailableReactions) -> String? {
    switch reactions {
    case .chatAvailableReactionsAll:
        nil
    case .chatAvailableReactionsSome(let some):
        some.reactions.isEmpty ? "Off" : "\(some.reactions.count) enabled"
    }
}

func telegramSlowModeDescription(_ seconds: Int) -> String {
    switch seconds {
    case ..<60: "\(seconds)s"
    case ..<3600:
        seconds % 60 == 0 ? "\(seconds / 60) min" : "\(seconds / 60) min \(seconds % 60)s"
    default:
        seconds % 3600 == 0 ? "\(seconds / 3600) h" : "\(seconds / 3600) h \((seconds % 3600) / 60) min"
    }
}

func telegramBirthdateDescription(_ birthdate: Birthdate) -> String {
    let calendar = Calendar.autoupdatingCurrent
    let now = Date()
    var components = DateComponents()
    components.calendar = calendar
    components.day = birthdate.day
    components.month = birthdate.month
    components.year = birthdate.year == 0 ? 2000 : birthdate.year
    guard let date = components.date else { return "\(birthdate.day)/\(birthdate.month)" }

    var description = date.formatted(
        Date.FormatStyle()
            .month(.wide)
            .day()
            .year(birthdate.year == 0 ? .omitted : .defaultDigits),
    )
    if birthdate.year > 0 {
        let age = calendar.dateComponents([.year], from: date, to: now).year ?? 0
        if age >= 0 {
            description += ", \(age) years old"
        }
    }
    let today = calendar.dateComponents([.day, .month], from: now)
    if today.day == birthdate.day, today.month == birthdate.month {
        description += ", birthday today"
    }
    return description
}
