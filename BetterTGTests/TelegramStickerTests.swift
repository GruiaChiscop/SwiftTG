// TelegramStickerTests.swift

@testable import BetterTG
import CoreGraphics
import TDLibKit
import Testing

struct TelegramStickerTests {
    // MARK: Internal

    @Test func `presentation maps all TDLib sticker formats`() {
        #expect(presentation(format: .stickerFormatWebp).kind == .image)
        #expect(presentation(format: .stickerFormatTgs).kind == .vectorAnimation)
        #expect(presentation(format: .stickerFormatWebm).kind == .video)
    }

    @Test func `presentation preserves files emoji and fitted dimensions`() {
        let thumbnail = Thumbnail(
            file: TDLibFixtures.file(id: 22, downloadedSize: 0),
            format: .thumbnailFormatJpeg,
            height: 128,
            width: 256,
        )
        let presentation = presentation(
            format: .stickerFormatTgs,
            emoji: "👋",
            height: 256,
            thumbnail: thumbnail,
            width: 512,
        )

        #expect(presentation.fileId == 11)
        #expect(presentation.thumbnailFileId == 22)
        #expect(presentation.accessibilityLabel == "Sticker 👋")
        #expect(presentation.displaySize() == CGSize(width: 224, height: 112))
    }

    @Test func `invalid sender dimensions use Telegram square fallback`() {
        let presentation = presentation(
            format: .stickerFormatWebp,
            height: 0,
            width: 0,
        )

        #expect(presentation.displaySize() == CGSize(width: 224, height: 224))
    }

    // MARK: Private

    private func presentation(
        format: StickerFormat,
        emoji: String = "",
        height: Int = 512,
        thumbnail: Thumbnail? = nil,
        width: Int = 512,
    ) -> TelegramStickerPresentation {
        TelegramStickerPresentation(Sticker(
            emoji: emoji,
            format: format,
            fullType: .stickerFullTypeRegular(.init(premiumAnimation: nil)),
            height: height,
            id: 1,
            setId: 2,
            sticker: TDLibFixtures.file(id: 11, downloadedSize: 0),
            thumbnail: thumbnail,
            width: width,
        ))
    }
}
