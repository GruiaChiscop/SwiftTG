// TelegramComposerInputModeTests.swift

@testable import BetterTG
import Testing

struct TelegramComposerInputModeTests {
    @Test func `media mode keeps a keyboard return action but disables text controls`() {
        let mode = TelegramComposerInputMode.media

        #expect(!mode.allowsTextControls)
        #expect(mode.mediaButtonTitle == "Return to Keyboard")
        #expect(mode.mediaButtonSystemImage == "keyboard")
    }

    @Test func `text mode exposes the media picker action and enables text controls`() {
        let mode = TelegramComposerInputMode.text

        #expect(mode.allowsTextControls)
        #expect(mode.mediaButtonTitle == "Stickers and GIFs")
        #expect(mode.mediaButtonSystemImage == "face.smiling")
    }
}
