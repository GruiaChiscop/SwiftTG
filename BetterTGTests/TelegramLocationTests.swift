// TelegramLocationTests.swift

@testable import BetterTG
import Testing

struct TelegramLocationTests {
    @Test func `draft without a fetched location is invalid`() {
        let draft = TelegramLocationDraft()
        #expect(!draft.isValid)
    }

    @Test func `draft requires both latitude and longitude`() {
        var draft = TelegramLocationDraft()
        draft.latitude = 45.0
        #expect(!draft.isValid)

        draft.latitude = nil
        draft.longitude = 25.0
        #expect(!draft.isValid)
    }

    @Test func `draft with coordinates builds location content`() throws {
        var draft = TelegramLocationDraft()
        draft.latitude = 44.4268
        draft.longitude = 26.1025
        draft.horizontalAccuracy = 12.5
        #expect(draft.isValid)

        let content = try draft.inputMessageContent()
        guard case .inputMessageLocation(let input) = content else {
            Issue.record("Expected location message content")
            return
        }
        #expect(input.location.latitude == 44.4268)
        #expect(input.location.longitude == 26.1025)
        #expect(input.location.horizontalAccuracy == 12.5)
    }

    @Test func `missing coordinates throws locationRequired`() {
        let draft = TelegramLocationDraft()
        #expect(throws: TelegramLocationDraftValidationError.locationRequired) {
            try draft.inputMessageContent()
        }
    }
}
