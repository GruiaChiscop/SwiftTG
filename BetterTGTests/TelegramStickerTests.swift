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

    @Test func `picker labels identify stickers without exposing their format`() {
        let presentation = presentation(format: .stickerFormatTgs, emoji: "👋")

        #expect(presentation.pickerAccessibilityLabel(packTitle: "Greetings") == "Sticker, 👋, from Greetings")
    }

    @Test func `premium stickers are identified from their premium animation`() {
        let presentation = presentation(
            format: .stickerFormatTgs,
            emoji: "💃",
            isPremium: true,
        )

        #expect(presentation.isPremium)
        #expect(presentation.pickerAccessibilityLabel(packTitle: "Hot Cherry") == "Premium sticker, 💃, from Hot Cherry")
    }

    @Test func `sending reuses the existing sticker file and metadata`() {
        let sticker = sticker(format: .stickerFormatWebm, emoji: "🎉", height: 320, width: 480)
        let content = TelegramStickerSending.content(for: sticker)
        guard case .inputMessageSticker(let input) = content else {
            Issue.record("Expected sticker message content")
            return
        }
        guard case .inputFileId(let file) = input.sticker.sticker else {
            Issue.record("Expected an existing TDLib file identifier")
            return
        }

        #expect(input.emoji == "🎉")
        #expect(input.sticker.height == 320)
        #expect(input.sticker.width == 480)
        #expect(input.sticker.thumbnail == nil)
        #expect(file.id == 11)
    }

    @Test func `duplicate stickers are removed without changing order`() {
        let first = sticker(format: .stickerFormatWebp, emoji: "1️⃣", fileId: 11)
        let duplicate = sticker(format: .stickerFormatTgs, emoji: "2️⃣", fileId: 11)
        let second = sticker(format: .stickerFormatWebm, emoji: "3️⃣", fileId: 12)

        #expect(telegramUniqueStickers([first, duplicate, second]).map(\.sticker.id) == [11, 12])
    }

    // MARK: Private

    private func presentation(
        format: StickerFormat,
        emoji: String = "",
        height: Int = 512,
        isPremium: Bool = false,
        thumbnail: Thumbnail? = nil,
        width: Int = 512,
    ) -> TelegramStickerPresentation {
        TelegramStickerPresentation(sticker(
            format: format,
            emoji: emoji,
            height: height,
            isPremium: isPremium,
            thumbnail: thumbnail,
            width: width,
        ))
    }

    private func sticker(
        format: StickerFormat,
        emoji: String = "",
        fileId: Int = 11,
        height: Int = 512,
        isPremium: Bool = false,
        thumbnail: Thumbnail? = nil,
        width: Int = 512,
    ) -> Sticker {
        Sticker(
            emoji: emoji,
            format: format,
            fullType: .stickerFullTypeRegular(.init(
                premiumAnimation: isPremium ? TDLibFixtures.file(id: 99, downloadedSize: 0) : nil,
            )),
            height: height,
            id: 1,
            setId: 2,
            sticker: TDLibFixtures.file(id: fileId, downloadedSize: 0),
            thumbnail: thumbnail,
            width: width,
        )
    }
}
