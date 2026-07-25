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
}
