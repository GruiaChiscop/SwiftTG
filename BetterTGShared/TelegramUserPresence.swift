// TelegramUserPresence.swift

import Foundation
import TDLibKit

func telegramUserPresenceDescription(
    _ status: UserStatus,
    now: Foundation.Date = Foundation.Date(),
    calendar: Calendar = .autoupdatingCurrent,
) -> String {
    switch status {
    case .userStatusOnline(let value):
        // The server's online window can lapse without a fresh `updateUserStatus` (the client was
        // backgrounded, the socket dropped). Once `expires` is in the past, fall back to a
        // "last seen" line built from that timestamp rather than showing a stale "Online" - this is
        // what Unigram's `LastSeenConverter.GetLabel` does too.
        if TimeInterval(value.expires) > now.timeIntervalSince1970 {
            return "Online"
        }
        return lastSeenDescription(unixTime: value.expires, now: now, calendar: calendar)
    case .userStatusOffline(let value):
        guard value.wasOnline > 0 else { return "Offline" }
        return lastSeenDescription(unixTime: value.wasOnline, now: now, calendar: calendar)
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

/// Upper bound on how far ahead `telegramPresencePhraseChangeDelay` will schedule, so a bogus
/// far-future `expires` from the server can't arm a multi-day sleep. Unigram clamps the same
/// computation to one day.
let telegramPresenceMaxRefreshDelay: TimeInterval = 24 * 60 * 60

/// Seconds from `now` until `telegramUserPresenceDescription` would render `status` differently, or
/// `nil` when the text is already stable. The only self-driven change our formatter has is an
/// online window lapsing - it renders absolute "last seen" times, so (unlike Unigram's relative
/// phrasing) there's no per-minute re-tick afterwards. Callers arm a single one-shot timer with the
/// result and recompute from the same `status` when it fires.
func telegramPresencePhraseChangeDelay(
    for status: UserStatus,
    now: Foundation.Date = Foundation.Date(),
    maximum: TimeInterval = telegramPresenceMaxRefreshDelay,
) -> TimeInterval? {
    guard case .userStatusOnline(let online) = status else { return nil }
    let remaining = TimeInterval(online.expires) - now.timeIntervalSince1970
    guard remaining > 0 else { return nil }
    return Swift.min(remaining, maximum)
}

private func lastSeenDescription(
    unixTime: Int,
    now: Foundation.Date,
    calendar: Calendar,
) -> String {
    let date = Foundation.Date(timeIntervalSince1970: TimeInterval(unixTime))
    if calendar.isDate(date, inSameDayAs: now) {
        return "Last seen today at \(date.formatted(date: .omitted, time: .shortened))"
    }
    if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
       calendar.isDate(date, inSameDayAs: yesterday)
    {
        return "Last seen yesterday at \(date.formatted(date: .omitted, time: .shortened))"
    }
    return "Last seen \(date.formatted(date: .abbreviated, time: .shortened))"
}
