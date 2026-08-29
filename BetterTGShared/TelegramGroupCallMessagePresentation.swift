// TelegramGroupCallMessagePresentation.swift

import Foundation
import TDLibKit

// MARK: - TelegramGroupCallMessagePresentation

/// Presentation rules for standalone conference messages. Telegram keeps a new unanswered
/// conference in its incoming/outgoing state for 30 seconds, then presents it as missed.
struct TelegramGroupCallMessagePresentation: Equatable {
    // MARK: Lifecycle

    init(
        content: MessageGroupCall,
        isOutgoing: Bool,
        messageDate: Int,
        now: Foundation.Date = Foundation.Date(),
    ) {
        self.isOutgoing = isOutgoing
        self.isVideo = content.isVideo
        self.duration = content.duration
        self.participantCount = content.otherParticipantIds.isEmpty
            ? nil
            : content.otherParticipantIds.count + 1

        let hasTimedOut = content.duration == 0
            && messageDate < Int(now.timeIntervalSince1970) - Self.missedTimeout
        if content.wasMissed {
            self.title = "Declined Group Call"
            self.isSuccessful = false
        } else if hasTimedOut {
            self.title = "Missed Group Call"
            self.isSuccessful = false
        } else {
            self.title = isOutgoing ? "Outgoing Group Call" : "Incoming Group Call"
            self.isSuccessful = true
        }
    }

    // MARK: Internal

    static let missedTimeout = 30

    let title: String
    let duration: Int
    let participantCount: Int?
    let isOutgoing: Bool
    let isVideo: Bool
    let isSuccessful: Bool

    var durationDescription: String? {
        guard duration > 1 else { return nil }
        return telegramCallDurationDescription(duration)
    }

    var participantDescription: String? {
        guard let participantCount else { return nil }
        return "\(participantCount) \(participantCount == 1 ? "participant" : "participants")"
    }

    var contentDescription: String {
        [title, durationDescription.map { "duration \($0)" }, participantDescription]
            .compactMap(\.self)
            .joined(separator: ", ")
    }

    var directionSystemImage: String {
        isOutgoing ? "arrow.up.right" : "arrow.down.left"
    }

    var callSystemImage: String {
        isVideo ? "video.fill" : "phone.fill"
    }
}
