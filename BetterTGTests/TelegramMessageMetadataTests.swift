// TelegramMessageMetadataTests.swift

@testable import BetterTG
import Foundation
import TDLibKit
import Testing

struct TelegramMessageMetadataTests {
    @Test func `day headings expose today and yesterday`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 14, hour: 12)))
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: now))

        #expect(telegramMessageDayHeading(Int(now.timeIntervalSince1970), relativeTo: now, calendar: calendar) ==
            "Today")
        #expect(telegramMessageDayHeading(Int(yesterday.timeIntervalSince1970), relativeTo: now, calendar: calendar) ==
            "Yesterday")
    }

    @Test func `delivery status is only exposed for outgoing messages`() {
        let incoming = TDLibFixtures.message(id: 10, chatId: 1, date: 100)
        let outgoing = TDLibFixtures.message(id: 11, chatId: 1, date: 100, isOutgoing: true)

        #expect(telegramMessageDeliveryStatus(incoming, lastReadOutboxMessageId: 100) == nil)
        #expect(telegramMessageDeliveryStatus(outgoing, lastReadOutboxMessageId: 10) == "Sent")
        #expect(telegramMessageDeliveryStatus(outgoing, lastReadOutboxMessageId: 11) == "Seen")
    }

    @Test func `pending status takes precedence over read state`() {
        let pending = TDLibFixtures.message(
            id: 12,
            chatId: 1,
            date: 100,
            isOutgoing: true,
            sendingState: .messageSendingStatePending(.init(sendingId: 7)),
        )

        #expect(telegramMessageDeliveryStatus(pending, lastReadOutboxMessageId: 12) == "Sending")
    }

    @Test func `edited status follows TDLib edit date`() {
        let original = TDLibFixtures.message(id: 20, chatId: 1, date: 100)
        let edited = TDLibFixtures.message(id: 21, chatId: 1, date: 100, editDate: 110)

        #expect(telegramMessageEditStatus(original) == nil)
        #expect(telegramMessageEditStatus(edited) == "Edited")
    }

    @Test func `voice durations have compact and spoken representations`() {
        #expect(telegramClockDuration(65) == "1:05")
        #expect(telegramClockDuration(-1) == "0:00")
        #expect(telegramVoicePlaybackDescription(duration: 65, elapsed: 12) ==
            "Duration 1 minute 5 seconds, played 12 seconds")
    }

    @Test func `quoted message excerpt normalizes whitespace and limits characters`() {
        #expect(telegramQuotedMessageExcerpt("First\n  second", characterLimit: 20) == "First second")
        #expect(telegramQuotedMessageExcerpt("123456789", characterLimit: 5) == "12345…")
    }

    @Test func `document description includes file name and caption`() {
        let document = Document(
            document: TDLibFixtures.file(id: 7, downloadedSize: 0),
            fileName: "report.pdf",
            mimeType: "application/pdf",
            minithumbnail: nil,
            thumbnail: nil,
        )
        let withoutCaption = MessageContent.messageDocument(.init(
            caption: FormattedText(entities: [], text: ""),
            document: document,
        ))
        let withCaption = MessageContent.messageDocument(.init(
            caption: FormattedText(entities: [], text: "Final version"),
            document: document,
        ))

        #expect(telegramMessageContentDescription(withoutCaption) == "File: report.pdf")
        #expect(telegramMessageContentDescription(withCaption) == "File: report.pdf, Final version")
    }

    @Test func `service messages have useful immediate descriptions`() {
        #expect(telegramMessageContentDescription(.messageChatJoinByLink) ==
            "A member joined via an invite link")
        #expect(telegramMessageContentDescription(.messageChatAddMembers(.init(memberUserIds: [2]))) ==
            "New members were added")
        #expect(telegramMessageContentDescription(.messageCustomServiceAction(.init(text: "Custom event"))) ==
            "Custom event")
    }

    @Test func `reaction choices are deduplicated and include a chosen removable reaction`() {
        let heart = ReactionType.reactionTypeEmoji(.init(emoji: "❤"))
        let thumbsUp = ReactionType.reactionTypeEmoji(.init(emoji: "👍"))
        let existing = [MessageReaction(
            isChosen: true,
            recentSenderIds: [],
            totalCount: 2,
            type: heart,
            usedSenderId: nil,
        )]
        let available = [
            AvailableReaction(needsPremium: false, type: heart),
            AvailableReaction(needsPremium: false, type: thumbsUp),
        ]

        #expect(telegramReactionChoices(existing: existing, available: available) == [heart, thumbsUp])
        #expect(telegramReactionActionTitle(heart, existing: existing) == "Remove reaction ❤")
        #expect(telegramReactionDescription(existing) == "Reactions: ❤ 2 in total. You also reacted")
    }
}
