// TelegramCallMessagePresentation.swift

import Foundation
import TDLibKit

// MARK: - TelegramCallMessagePresentation

struct TelegramCallMessagePresentation: Equatable {
    // MARK: Lifecycle

    init(content: MessageCall, isOutgoing: Bool) {
        self.isOutgoing = isOutgoing
        self.isVideo = content.isVideo
        self.duration = content.duration

        let unsuccessful =
            switch content.discardReason {
            case .callDiscardReasonDeclined,
                 .callDiscardReasonDisconnected,
                 .callDiscardReasonMissed:
                true
            case .callDiscardReasonEmpty,
                 .callDiscardReasonHungUp,
                 .callDiscardReasonUpgradeToGroupCall:
                false
            }
        self.isSuccessful = !unsuccessful

        self.title =
            switch content.discardReason {
            case .callDiscardReasonDisconnected:
                Self.cancelledTitle(isVideo: content.isVideo)
            case .callDiscardReasonDeclined,
                 .callDiscardReasonMissed:
                Self.unsuccessfulTitle(isOutgoing: isOutgoing, isVideo: content.isVideo)
            case .callDiscardReasonEmpty,
                 .callDiscardReasonHungUp,
                 .callDiscardReasonUpgradeToGroupCall:
                Self.completedTitle(isOutgoing: isOutgoing, isVideo: content.isVideo)
            }
    }

    // MARK: Internal

    let title: String
    let duration: Int
    let isOutgoing: Bool
    let isVideo: Bool
    let isSuccessful: Bool

    var durationDescription: String? {
        guard duration > 1 else { return nil }
        return telegramCallDurationDescription(duration)
    }

    var contentDescription: String {
        guard let durationDescription else { return title }
        return "\(title), duration \(durationDescription)"
    }

    var directionSystemImage: String {
        isOutgoing ? "arrow.up.right" : "arrow.down.left"
    }

    var callSystemImage: String {
        isVideo ? "video.fill" : "phone.fill"
    }

    // MARK: Private

    private static func completedTitle(isOutgoing: Bool, isVideo: Bool) -> String {
        switch (isOutgoing, isVideo) {
        case (true, true): "Outgoing Video Call"
        case (true, false): "Outgoing Call"
        case (false, true): "Incoming Video Call"
        case (false, false): "Incoming Call"
        }
    }

    private static func cancelledTitle(isVideo: Bool) -> String {
        isVideo ? "Cancelled Video Call" : "Cancelled Call"
    }

    private static func unsuccessfulTitle(isOutgoing: Bool, isVideo: Bool) -> String {
        switch (isOutgoing, isVideo) {
        case (true, true): "Cancelled Video Call"
        case (true, false): "Cancelled Call"
        case (false, true): "Missed Video Call"
        case (false, false): "Missed Call"
        }
    }
}

func telegramCallDurationDescription(_ seconds: Int) -> String {
    let value = max(1, seconds)
    if value < 60 {
        return "\(value) \(value == 1 ? "second" : "seconds")"
    }
    if value < 3600 {
        let minutes = max(1, value / 60)
        return "\(minutes) \(minutes == 1 ? "minute" : "minutes")"
    }
    if value < 86400 {
        let hours = max(1, value / 3600)
        return "\(hours) \(hours == 1 ? "hour" : "hours")"
    }
    let days = max(1, value / 86400)
    return "\(days) \(days == 1 ? "day" : "days")"
}
