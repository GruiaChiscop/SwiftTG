// TelegramUserPresence.swift

import Foundation
import TDLibKit

func telegramUserPresenceDescription(
    _ status: UserStatus,
    now: Foundation.Date = Foundation.Date(),
    calendar: Calendar = .autoupdatingCurrent,
) -> String {
    switch status {
    case .userStatusOnline:
        return "Online"
    case .userStatusOffline(let value):
        guard value.wasOnline > 0 else { return "Offline" }
        let date = Foundation.Date(timeIntervalSince1970: TimeInterval(value.wasOnline))
        if calendar.isDate(date, inSameDayAs: now) {
            return "Last seen today at \(date.formatted(date: .omitted, time: .shortened))"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday)
        {
            return "Last seen yesterday at \(date.formatted(date: .omitted, time: .shortened))"
        }
        return "Last seen \(date.formatted(date: .abbreviated, time: .shortened))"
    case .userStatusRecently:
        return "Last seen recently"
    case .userStatusLastWeek:
        return "Last seen within a week"
    case .userStatusLastMonth:
        return "Last seen within a month"
    case .userStatusEmpty:
        return "Last seen a long time ago"
    }
}
