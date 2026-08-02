// TelegramDraftsTests.swift

@testable import BetterTG
import Foundation
import TDLibKit
import Testing

struct TelegramDraftsTests {
    @Test func `empty composer clears the draft`() {
        #expect(TelegramDrafts.make(text: "", replyMessageId: nil) == nil)
    }

    @Test func `text draft round trips`() throws {
        let date = Foundation.Date(timeIntervalSince1970: 123)
        let draft = try #require(TelegramDrafts.make(text: "Unsent message", replyMessageId: nil, date: date))

        #expect(TelegramDrafts.text(from: draft) == "Unsent message")
        #expect(TelegramDrafts.replyMessageId(from: draft) == nil)
        #expect(draft.date == 123)
    }

    @Test func `reply-only draft preserves the target message`() throws {
        let draft = try #require(TelegramDrafts.make(text: "", replyMessageId: 456))

        #expect(TelegramDrafts.text(from: draft).isEmpty)
        #expect(TelegramDrafts.replyMessageId(from: draft) == 456)
    }

    @Test func `formatted draft preserves its entities`() throws {
        let bold = TextEntity(length: 4, offset: 0, type: .textEntityTypeBold)
        let text = FormattedText(entities: [bold], text: "Bold draft")
        let draft = try #require(TelegramDrafts.make(formattedText: text, replyMessageId: nil))
        guard case .draftMessageContentText(let content) = draft.content else {
            Issue.record("Expected a text draft")
            return
        }

        #expect(content.text == text)
        #expect(TelegramDrafts.formattedText(from: draft) == text)
    }

    @Test func `empty formatted composer clears the draft`() {
        let text = FormattedText(entities: [], text: "")

        #expect(TelegramDrafts.make(formattedText: text, replyMessageId: nil) == nil)
    }

    @Test func `chat list preview prefers the draft date`() throws {
        let draft = try #require(TelegramDrafts.make(
            text: "Draft",
            replyMessageId: nil,
            date: Foundation.Date(timeIntervalSince1970: 200),
        ))
        let lastMessage = TDLibFixtures.message(id: 1, chatId: 1, date: 100)

        #expect(TelegramDrafts.previewDate(draft: draft, lastMessage: lastMessage) == 200)
        #expect(TelegramDrafts.previewDate(draft: nil, lastMessage: lastMessage) == 100)
    }
}
