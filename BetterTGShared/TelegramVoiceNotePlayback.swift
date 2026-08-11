// TelegramVoiceNotePlayback.swift

import TDLibKit

struct TelegramVoiceNotePresentation: Equatable {
    // MARK: Lifecycle

    init(message: Message, content: MessageVoiceNote) {
        self.duration = max(0, content.voiceNote.duration)
        self.isOutgoing = message.isOutgoing
        self.isViewOnce = message.selfDestructType == .messageSelfDestructTypeImmediately
    }

    // MARK: Internal

    let duration: Int
    let isOutgoing: Bool
    let isViewOnce: Bool

    var allowsSeeking: Bool { !isViewOnce }
    var shouldOpenMessageContent: Bool { isViewOnce && !isOutgoing }

    var accessibilityDetails: String {
        var parts = [String]()
        if isViewOnce {
            parts.append("view once")
        }
        parts.append("duration \(telegramSpokenDuration(duration))")
        return parts.joined(separator: ", ")
    }
}
