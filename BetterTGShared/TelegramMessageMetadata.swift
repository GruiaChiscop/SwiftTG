// TelegramMessageMetadata.swift

import Foundation
import TDLibKit

func telegramMessageContentDescription(_ message: Message) -> String {
    telegramMessageContentDescription(message.content)
}

func telegramMessageFormattedText(_ message: Message) -> FormattedText? {
    switch message.content {
    case .messageAudio(let content): content.caption.text.isEmpty ? nil : content.caption
    case .messageDocument(let content): content.caption.text.isEmpty ? nil : content.caption
    case .messagePhoto(let content): content.caption.text.isEmpty ? nil : content.caption
    case .messageText(let content): content.text.text.isEmpty ? nil : content.text
    case .messageVideo(let content): content.caption.text.isEmpty ? nil : content.caption
    case .messageVoiceNote(let content): content.caption.text.isEmpty ? nil : content.caption
    default: nil
    }
}

func telegramMessageContentDescription(_ content: MessageContent) -> String {
    switch content {
    case .messageText(let content):
        content.text.text
    case .messagePhoto(let content):
        content.caption.text.isEmpty ? "Photo" : "Photo: \(content.caption.text)"
    case .messageVoiceNote(let content):
        content.caption.text.isEmpty ? "Voice message" : "Voice message: \(content.caption.text)"
    case .messageAudio(let content):
        telegramAudioDescription(content)
    case .messageVideo(let content):
        content.caption.text.isEmpty ? "Video" : "Video: \(content.caption.text)"
    case .messageDocument(let content):
        content.caption.text.isEmpty
            ? "File: \(content.document.fileName)"
            : "File: \(content.document.fileName), \(content.caption.text)"
    case .messageSticker(let content):
        content.sticker.emoji.isEmpty ? "Sticker" : "Sticker \(content.sticker.emoji)"
    case .messageCall:
        "Call"
    case .messageBasicGroupChatCreate, .messageSupergroupChatCreate:
        "Group created"
    case .messageChatChangeTitle:
        "Group name changed"
    case .messageChatChangePhoto:
        "Group photo changed"
    case .messageChatDeletePhoto:
        "Group photo removed"
    case .messageChatAddMembers:
        "New members were added"
    case .messageChatJoinByLink:
        "A member joined via an invite link"
    case .messageChatJoinByRequest:
        "A member joined the group"
    case .messageChatDeleteMember:
        "A member left or was removed"
    case .messageChatOwnerChanged, .messageChatOwnerLeft:
        "Group owner changed"
    case .messageChatUpgradeFrom, .messageChatUpgradeTo:
        "Group upgraded"
    case .messagePinMessage:
        "A message was pinned"
    case .messageScreenshotTaken:
        "Screenshot taken"
    case .messageChatSetMessageAutoDeleteTime:
        "Auto-delete settings changed"
    case .messageCustomServiceAction(let content):
        content.text
    case .messageUnsupported:
        "Unsupported message"
    default:
        "Message"
    }
}

func telegramQuotedMessageExcerpt(_ text: String, characterLimit: Int = 80) -> String {
    let normalized = text.split(whereSeparator: \Character.isWhitespace).joined(separator: " ")
    guard normalized.count > characterLimit else { return normalized }
    return String(normalized.prefix(max(0, characterLimit))).trimmingCharacters(in: .whitespaces) + "…"
}

func telegramMessageDateDescription(_ timestamp: Int) -> String {
    Date(timeIntervalSince1970: TimeInterval(timestamp)).formatted(date: .abbreviated, time: .shortened)
}

func telegramMessageDayHeading(
    _ timestamp: Int,
    relativeTo now: Foundation.Date = Foundation.Date(),
    calendar: Calendar = .autoupdatingCurrent,
) -> String {
    let date = Foundation.Date(timeIntervalSince1970: TimeInterval(timestamp))
    if calendar.isDate(date, inSameDayAs: now) {
        return "Today"
    }
    if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
       calendar.isDate(date, inSameDayAs: yesterday)
    {
        return "Yesterday"
    }

    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.locale = .autoupdatingCurrent
    formatter.timeZone = calendar.timeZone
    formatter.dateStyle = .long
    formatter.timeStyle = .none
    return formatter.string(from: date)
}

func telegramMessageEditStatus(_ message: Message) -> String? {
    message.editDate > 0 ? "Edited" : nil
}

func telegramMessageDeliveryStatus(_ message: Message, lastReadOutboxMessageId: Int64) -> String? {
    guard message.isOutgoing else { return nil }
    switch message.sendingState {
    case .messageSendingStatePending:
        return "Sending"
    case .messageSendingStateFailed:
        return "Failed to send"
    case nil:
        return message.id <= lastReadOutboxMessageId ? "Seen" : "Sent"
    }
}

func telegramVoicePlaybackDescription(duration: Int, elapsed: Int) -> String {
    "Duration \(telegramSpokenDuration(duration)), played \(telegramSpokenDuration(elapsed))"
}

func telegramAudioDescription(_ content: MessageAudio) -> String {
    var parts = ["Audio", telegramAudioTitle(content.audio)]
    if !content.audio.performer.isEmpty {
        parts.append("by \(content.audio.performer)")
    }
    parts.append("duration \(telegramClockDuration(content.audio.duration))")
    if !content.caption.text.isEmpty {
        parts.append(content.caption.text)
    }
    return parts.joined(separator: ", ")
}

func telegramAudioTitle(_ audio: Audio) -> String {
    if !audio.title.isEmpty {
        return audio.title
    }
    if !audio.fileName.isEmpty {
        return audio.fileName
    }
    return "Unknown track"
}

func telegramClockDuration(_ seconds: Int) -> String {
    String(format: "%d:%02d", max(0, seconds) / 60, max(0, seconds) % 60)
}

private func telegramSpokenDuration(_ seconds: Int) -> String {
    let value = max(0, seconds)
    let minutes = value / 60
    let remainingSeconds = value % 60
    if minutes == 0 {
        return "\(remainingSeconds) \(remainingSeconds == 1 ? "second" : "seconds")"
    }
    let minutePart = "\(minutes) \(minutes == 1 ? "minute" : "minutes")"
    guard remainingSeconds > 0 else { return minutePart }
    return "\(minutePart) \(remainingSeconds) \(remainingSeconds == 1 ? "second" : "seconds")"
}
