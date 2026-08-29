// TelegramMessageMetadata.swift

import Foundation
import TDLibKit

func telegramMessageContentDescription(_ message: Message) -> String {
    // `MessageSupergroupChatCreate` covers both supergroups and channels (TDLib doesn't
    // distinguish at the content level - a channel is a supergroup with no visible member
    // list) - `isChannelPost` is set on every message posted in a channel, so it's the only
    // way to tell them apart here.
    if case .messageSupergroupChatCreate = message.content, message.isChannelPost {
        return "Channel created"
    }
    if case .messageCall(let content) = message.content {
        return TelegramCallMessagePresentation(
            content: content,
            isOutgoing: message.isOutgoing,
        ).contentDescription
    }
    if case .messageGroupCall(let content) = message.content {
        return TelegramGroupCallMessagePresentation(
            content: content,
            isOutgoing: message.isOutgoing,
            messageDate: message.date,
        ).contentDescription
    }
    return telegramMessageContentDescription(message.content)
}

/// The chat list only receives TDLib's last message, not every member of its media album.
/// Match Telegram-iOS by preferring an album caption and otherwise identifying the grouped
/// media as an album, without guessing an item count that isn't available here.
func telegramChatListMessageDescription(_ message: Message) -> String {
    if case .messageCall(let content) = message.content {
        return TelegramCallMessagePresentation(
            content: content,
            isOutgoing: message.isOutgoing,
        ).title
    }
    if case .messageGroupCall(let content) = message.content {
        return TelegramGroupCallMessagePresentation(
            content: content,
            isOutgoing: message.isOutgoing,
            messageDate: message.date,
        ).title
    }
    guard message.mediaAlbumId != 0 else {
        return telegramMessageContentDescription(message)
    }
    if let caption = telegramMessageFormattedText(message)?.text, !caption.isEmpty {
        return caption
    }
    return "Album"
}

func telegramMessageFormattedText(_ message: Message) -> FormattedText? {
    switch message.content {
    case .messageAudio(let content): content.caption.text.isEmpty ? nil : content.caption
    case .messageDocument(let content): content.caption.text.isEmpty ? nil : content.caption
    case .messagePhoto(let content): content.caption.text.isEmpty ? nil : content.caption
    case .messageText(let content): content.text.text.isEmpty ? nil : content.text
    case .messageVideo(let content): content.caption.text.isEmpty ? nil : content.caption
    case .messageVideoNote: nil
    case .messageVoiceNote(let content): content.caption.text.isEmpty ? nil : content.caption
    case .messageAnimation(let content): content.caption.text.isEmpty ? nil : content.caption
    default: nil
    }
}

func telegramMessageContentDescription(_ content: MessageContent) -> String {
    switch content {
    case .messageText(let content):
        if let preview = content.linkPreview {
            [content.text.text, TelegramLinkPreviewPresentation(preview).accessibilityDescription]
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
        } else {
            content.text.text
        }
    case .messagePhoto(let content):
        content.caption.text.isEmpty ? "Photo" : "Photo: \(content.caption.text)"
    case .messageVoiceNote(let content):
        content.caption.text.isEmpty ? "Voice message" : "Voice message: \(content.caption.text)"
    case .messageExpiredVoiceNote:
        "Voice message expired"
    case .messageAudio(let content):
        telegramAudioDescription(content)
    case .messageVideo(let content):
        content.caption.text.isEmpty ? "Video" : "Video: \(content.caption.text)"
    case .messageVideoNote:
        "Video message"
    case .messageExpiredVideoNote:
        "Video message expired"
    case .messageAnimation(let content):
        content.caption.text.isEmpty ? "GIF" : "GIF: \(content.caption.text)"
    case .messageDocument(let content):
        content.caption.text.isEmpty
            ? "File: \(content.document.fileName)"
            : "File: \(content.document.fileName), \(content.caption.text)"
    case .messagePoll(let content):
        TelegramPollPresentation(content).contentDescription
    case .messageChecklist(let content):
        TelegramChecklistPresentation(content).contentDescription
    case .messageContact(let content):
        TelegramContactPresentation(content).contentDescription
    case .messageLiveLocation, .messageLocation, .messageVenue:
        TelegramLocationPresentation(content)?.contentDescription ?? "Location"
    case .messageSticker(let content):
        content.sticker.emoji.isEmpty ? "Sticker" : "Sticker \(content.sticker.emoji)"
    case .messageCall:
        "Call"
    case .messageGroupCall(let content):
        content.wasMissed ? "Declined Group Call" : "Group Call"
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

/// Short label for a chat list row's preview date: just the time for today, otherwise the date -
/// showing a bare time for an old message would misread as "sent today".
func telegramChatListTimestamp(
    _ timestamp: Int,
    relativeTo now: Foundation.Date = Foundation.Date(),
    calendar: Calendar = .autoupdatingCurrent,
) -> String {
    let date = Foundation.Date(timeIntervalSince1970: TimeInterval(timestamp))
    if calendar.isDate(date, inSameDayAs: now) {
        return date.formatted(date: .omitted, time: .shortened)
    }
    return date.formatted(.dateTime.month(.abbreviated).day())
}

/// Date label for a Recent Calls row: always carries the time (a call list has few rows and the
/// time matters), with a relative day name for anything within the past week.
func telegramCallListTimestamp(
    _ timestamp: Int,
    relativeTo now: Foundation.Date = Foundation.Date(),
    calendar: Calendar = .autoupdatingCurrent,
) -> String {
    let date = Foundation.Date(timeIntervalSince1970: TimeInterval(timestamp))
    let time = date.formatted(date: .omitted, time: .shortened)
    if calendar.isDateInToday(date) {
        return time
    }
    if calendar.isDateInYesterday(date) {
        return "Yesterday \(time)"
    }
    let dayGap = calendar.dateComponents(
        [.day],
        from: calendar.startOfDay(for: date),
        to: calendar.startOfDay(for: now),
    )
    .day ?? .max
    if (1..<7).contains(dayGap) {
        return "\(date.formatted(.dateTime.weekday(.abbreviated))) \(time)"
    }
    if calendar.isDate(date, equalTo: now, toGranularity: .year) {
        return "\(date.formatted(.dateTime.month(.abbreviated).day())), \(time)"
    }
    return "\(date.formatted(.dateTime.year().month(.abbreviated).day())), \(time)"
}

/// Call duration as `m:ss`, or `h:mm:ss` once it passes an hour.
func telegramCallDurationClock(_ seconds: Int) -> String {
    let value = max(0, seconds)
    let hours = value / 3600
    let minutes = (value % 3600) / 60
    let remainingSeconds = value % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
    }
    return String(format: "%d:%02d", minutes, remainingSeconds)
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

func telegramSpokenDuration(_ seconds: Int) -> String {
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
