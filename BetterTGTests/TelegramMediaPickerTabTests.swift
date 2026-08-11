// TelegramMediaPickerTabTests.swift

@testable import BetterTG
import Testing

struct TelegramMediaPickerTabTests {
    @Test func `stored selection restores valid tabs and safely defaults to stickers`() {
        #expect(TelegramMediaPickerTab.selection(storedValue: "gifs") == .gifs)
        #expect(TelegramMediaPickerTab.selection(storedValue: "stickers") == .stickers)
        #expect(TelegramMediaPickerTab.selection(storedValue: "unknown") == .stickers)
    }
}
