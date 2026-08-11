// TelegramMessageGifSavingTests.swift

@testable import BetterTG
import TDLibKit
import Testing

struct TelegramMessageGifSavingTests {
    // MARK: Internal

    @Test func `animation messages expose their GIF for saving`() {
        let animation = animation(fileId: 41)
        let message = TDLibFixtures.message(
            id: 1,
            chatId: 2,
            date: 3,
            content: .messageAnimation(.init(
                animation: animation,
                caption: .init(entities: [], text: ""),
                hasSpoiler: false,
                isSecret: false,
                showCaptionAboveMedia: false,
            )),
        )

        #expect(TelegramMessageGifSaving.fileID(from: message) == 41)
    }

    @Test func `animation link previews expose their GIF for saving`() {
        let animation = animation(fileId: 42)
        let preview = LinkPreview(
            author: "",
            description: .init(entities: [], text: ""),
            displayUrl: "example.com",
            hasLargeMedia: false,
            instantViewVersion: 0,
            showAboveText: false,
            showLargeMedia: false,
            showMediaAboveDescription: false,
            siteName: "Example",
            skipConfirmation: true,
            title: "GIF",
            type: .linkPreviewTypeAnimation(.init(animation: animation)),
            url: "https://example.com/gif",
        )
        let message = TDLibFixtures.message(id: 1, chatId: 2, date: 3, linkPreview: preview)

        #expect(TelegramMessageGifSaving.fileID(from: message) == 42)
    }

    @Test func `protected and non-GIF messages cannot be saved as GIFs`() {
        let protected = TDLibFixtures.message(
            id: 1,
            chatId: 2,
            date: 3,
            canBeSaved: false,
            content: .messageAnimation(.init(
                animation: animation(fileId: 43),
                caption: .init(entities: [], text: ""),
                hasSpoiler: false,
                isSecret: false,
                showCaptionAboveMedia: false,
            )),
        )
        let text = TDLibFixtures.message(id: 2, chatId: 2, date: 3)

        #expect(TelegramMessageGifSaving.fileID(from: protected) == nil)
        #expect(TelegramMessageGifSaving.fileID(from: text) == nil)
    }

    // MARK: Private

    private func animation(fileId: Int) -> TDLibKit.Animation {
        TDLibKit.Animation(
            animation: TDLibFixtures.file(id: fileId, downloadedSize: 0),
            duration: 1,
            fileName: "animation.mp4",
            hasStickers: false,
            height: 360,
            mimeType: "video/mp4",
            minithumbnail: nil,
            thumbnail: nil,
            width: 640,
        )
    }
}
