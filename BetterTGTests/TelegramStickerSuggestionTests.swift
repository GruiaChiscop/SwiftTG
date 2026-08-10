// TelegramStickerSuggestionTests.swift

@testable import BetterTG
import Testing

struct TelegramStickerSuggestionTests {
    @Test func `single emoji produces a suggestion query`() {
        #expect(TelegramStickerSuggestionQuery.emoji(from: "👋") == "👋")
        #expect(TelegramStickerSuggestionQuery.emoji(from: "👋🏽") == "👋🏽")
        #expect(TelegramStickerSuggestionQuery.emoji(from: "👨‍👩‍👧‍👦") == "👨‍👩‍👧‍👦")
        #expect(TelegramStickerSuggestionQuery.emoji(from: "🇷🇴") == "🇷🇴")
        #expect(TelegramStickerSuggestionQuery.emoji(from: "  ❤️\n") == "❤️")
    }

    @Test func `plain text and Unicode emoji-capable ASCII do not produce suggestions`() {
        for text in ["", "A", "hello", "1", "#", "*"] {
            #expect(TelegramStickerSuggestionQuery.emoji(from: text) == nil)
        }
    }

    @Test func `multiple characters do not produce suggestions`() {
        #expect(TelegramStickerSuggestionQuery.emoji(from: "👋👋") == nil)
        #expect(TelegramStickerSuggestionQuery.emoji(from: "hello 👋") == nil)
        #expect(TelegramStickerSuggestionQuery.emoji(from: "👋 hello") == nil)
    }
}
