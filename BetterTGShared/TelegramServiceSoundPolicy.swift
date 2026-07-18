// TelegramServiceSoundPolicy.swift

import Foundation

struct TelegramServiceSoundPolicy {
    // MARK: Lifecycle

    init(minimumInterval: TimeInterval = 0.2) {
        self.minimumInterval = minimumInterval
    }

    // MARK: Internal

    static let incomingResourceName = "notification"
    static let deliveredResourceName = "MessageSent"
    static let resourceExtension = "mp3"

    var minimumInterval: TimeInterval

    mutating func shouldPlayDelivered(now: Date = .now) -> Bool {
        guard now.timeIntervalSince(lastDeliveredPlayback) > minimumInterval else { return false }
        lastDeliveredPlayback = now
        return true
    }

    mutating func shouldPlayIncoming(
        applicationIsActive: Bool,
        isMuted: Bool,
        now: Date = .now,
    ) -> Bool {
        guard applicationIsActive, !isMuted else { return false }
        guard now.timeIntervalSince(lastIncomingPlayback) > minimumInterval else { return false }
        lastIncomingPlayback = now
        return true
    }

    // MARK: Private

    private var lastIncomingPlayback = Date.distantPast
    private var lastDeliveredPlayback = Date.distantPast
}
