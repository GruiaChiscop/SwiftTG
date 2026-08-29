// TelegramCallHistoryEntry.swift

import Foundation
import TDLibKit

/// One call/group-call message, classified for the Recent Calls list and its detail view.
struct TelegramCallHistoryEntry: Identifiable, Equatable {
    // MARK: Lifecycle

    init?(message: Message) {
        switch message.content {
        case .messageCall(let content):
            let presentation = TelegramCallMessagePresentation(
                content: content,
                isOutgoing: message.isOutgoing,
            )
            self.isConference = false
            self.isVideo = content.isVideo
            self.duration = content.duration
            self.otherParticipantIds = []
            self.isSuccessful = presentation.isSuccessful
            let missed: Bool =
                if case .callDiscardReasonMissed = content.discardReason {
                    !message.isOutgoing
                } else {
                    false
                }
            self.isMissed = missed

        case .messageGroupCall(let content):
            let presentation = TelegramGroupCallMessagePresentation(
                content: content,
                isOutgoing: message.isOutgoing,
                messageDate: message.date,
            )
            self.isConference = true
            self.isVideo = content.isVideo
            self.duration = content.duration
            self.otherParticipantIds = content.otherParticipantIds
            self.isSuccessful = presentation.isSuccessful
            self.isMissed = !message.isOutgoing && !presentation.isSuccessful

        default:
            return nil
        }

        self.message = message
        self.isOutgoing = message.isOutgoing

        let isCancelled = !isSuccessful && !isMissed
        self.shortStatus =
            if isMissed {
                "Missed"
            } else if isCancelled {
                "Cancelled"
            } else if message.isOutgoing {
                "Outgoing"
            } else {
                "Incoming"
            }
    }

    // MARK: Internal

    let message: Message
    let isOutgoing: Bool
    let isVideo: Bool
    let isConference: Bool
    let isMissed: Bool
    let isSuccessful: Bool
    let duration: Int
    let otherParticipantIds: [MessageSender]
    /// One word: "Missed", "Cancelled", "Incoming", "Outgoing".
    let shortStatus: String

    var id: Int64 { message.id }
    var chatId: Int64 { message.chatId }
    var date: Int { message.date }

    /// VoiceOver phrasing, e.g. "Missed video call", "Incoming group call".
    var spokenType: String {
        let kind = isConference ? "group call" : "call"
        let prefix = shortStatus.lowercased() == "incoming"
            ? "Incoming"
            : shortStatus.lowercased() == "outgoing"
                ? "Outgoing"
                : shortStatus
        return isVideo ? "\(prefix) video \(kind)" : "\(prefix) \(kind)"
    }
}
