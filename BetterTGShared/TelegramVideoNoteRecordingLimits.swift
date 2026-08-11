// TelegramVideoNoteRecordingLimits.swift

import Foundation

enum TelegramVideoNoteRecordingLimits {
    static let maximumDuration: TimeInterval = 60

    static func totalDuration(completed: TimeInterval, current: TimeInterval) -> TimeInterval {
        min(maximumDuration, max(0, completed) + max(0, current))
    }

    static func remainingDuration(after duration: TimeInterval) -> TimeInterval {
        max(0, maximumDuration - max(0, duration))
    }
}
