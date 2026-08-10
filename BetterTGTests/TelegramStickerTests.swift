// TelegramStickerTests.swift

@testable import BetterTG
import CoreGraphics
import Foundation
import ImageIO
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

    @Test func `editing is offered only for static nonpremium stickers`() {
        #expect(presentation(format: .stickerFormatWebp).isEditable)
        #expect(!presentation(format: .stickerFormatTgs).isEditable)
        #expect(!presentation(format: .stickerFormatWebm).isEditable)
        #expect(!presentation(format: .stickerFormatWebp, isPremium: true).isEditable)
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

    @Test func `edited sticker messages preserve rendered dimensions and emoji`() {
        let content = TelegramStickerEditing.messageContent(
            fileId: 77,
            emojis: "🎨",
            height: 384,
            width: 512,
        )
        guard case .inputMessageSticker(let input) = content,
              case .inputFileId(let file) = input.sticker.sticker
        else {
            Issue.record("Expected an edited sticker message")
            return
        }

        #expect(file.id == 77)
        #expect(input.emoji == "🎨")
        #expect(input.sticker.height == 384)
        #expect(input.sticker.width == 512)
    }

    @Test func `favorite actions update identifiers and labels consistently`() {
        let add = TelegramStickerFavoriteAction(isFavorite: false)
        let added = add.applying(to: [11], stickerFileId: 22)
        let remove = TelegramStickerFavoriteAction(isFavorite: added.contains(22))
        let removed = remove.applying(to: added, stickerFileId: 22)

        #expect(add.title == "Add to Favorites")
        #expect(add.systemImage == "star")
        #expect(added == [11, 22])
        #expect(remove.title == "Remove from Favorites")
        #expect(remove.systemImage == "star.slash")
        #expect(removed == [11])
    }

    @MainActor @Test func `sticker editor renders a Telegram sized PNG`() throws {
        let source = try #require(Self.solidColorImage(size: CGSize(width: 40, height: 20)))
        let pngData = try TelegramStickerEditorRendering.pngData(
            sourceImage: source,
            snapshot: .init(strokes: [], overlays: []),
        )
        let imageSource = try #require(CGImageSourceCreateWithData(pngData as CFData, nil))
        let rendered = try #require(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))

        #expect(rendered.width == TelegramStickerCropRendering.outputSide)
        #expect(rendered.height == TelegramStickerCropRendering.outputSide / 2)
    }

    @Test func `duplicate stickers are removed without changing order`() {
        let first = sticker(format: .stickerFormatWebp, emoji: "1️⃣", fileId: 11)
        let duplicate = sticker(format: .stickerFormatTgs, emoji: "2️⃣", fileId: 11)
        let second = sticker(format: .stickerFormatWebm, emoji: "3️⃣", fileId: 12)

        #expect(telegramUniqueStickers([first, duplicate, second]).map(\.sticker.id) == [11, 12])
    }

    @Test func `pack references require a real sticker set`() {
        let stickerWithPack = sticker(format: .stickerFormatWebp, setId: 42)
        let stickerWithoutPack = sticker(format: .stickerFormatWebp, setId: 0)

        #expect(TelegramStickerPackReference(sticker: stickerWithPack)?.id == 42)
        #expect(TelegramStickerPackReference(sticker: stickerWithoutPack) == nil)
    }

    @Test func `message stickers preserve their pack reference`() {
        let content = MessageSticker(
            isPremium: false,
            sticker: sticker(format: .stickerFormatWebp, setId: 84),
        )

        #expect(TelegramStickerPackReference(messageSticker: content)?.id == 84)
    }

    @Test func `pack installation actions match Telegram behavior`() {
        let install = TelegramStickerPackInstallationAction(
            isInstalled: false,
            isOwned: false,
            stickerCount: 12,
        )
        let remove = TelegramStickerPackInstallationAction(
            isInstalled: true,
            isOwned: false,
            stickerCount: 1,
        )

        #expect(install == .install(stickerCount: 12))
        #expect(install?.title == "Add 12 Stickers")
        #expect(remove == .remove(stickerCount: 1))
        #expect(remove?.title == "Remove 1 Sticker")
        #expect(TelegramStickerPackInstallationAction(
            isInstalled: true,
            isOwned: true,
            stickerCount: 4,
        ) == nil)
    }

    @Test func `editor overlay selection maps every sticker format`() {
        let url = URL(filePath: "/tmp/sticker")

        #expect(TelegramEditorOverlaySelection.sticker(
            fileURL: url,
            sticker: sticker(format: .stickerFormatWebp),
        )
        .format == .staticImage)
        #expect(TelegramEditorOverlaySelection.sticker(
            fileURL: url,
            sticker: sticker(format: .stickerFormatTgs),
        )
        .format == .tgs)
        #expect(TelegramEditorOverlaySelection.sticker(
            fileURL: url,
            sticker: sticker(format: .stickerFormatWebm),
        )
        .format == .webm)
    }

    @Test func `GIF overlay selection preserves dimensions and uses video rendering`() {
        let overlay = TelegramEditorOverlaySelection.gif(
            fileURL: URL(filePath: "/tmp/animation.mp4"),
            width: 640,
            height: 360,
        )

        #expect(overlay.pixelWidth == 640)
        #expect(overlay.pixelHeight == 360)
        #expect(overlay.format == .video)
        #expect(overlay.format.isAnimated)
    }

    @Test func `duplicate GIFs are removed without changing order`() {
        let first = animation(fileId: 41, width: 320, height: 180)
        let duplicate = animation(fileId: 41, width: 640, height: 360)
        let second = animation(fileId: 42, width: 200, height: 200)

        let unique = telegramUniqueAnimations([first, duplicate, second])

        #expect(unique.map(\.animation.id) == [41, 42])
        #expect(unique.first?.width == 320)
    }

    // MARK: Private

    private static func solidColorImage(size: CGSize) -> CGImage? {
        let width = Int(size.width)
        let height = Int(size.height)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ) else { return nil }
        context.setFillColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1)
        context.fill(CGRect(origin: .zero, size: size))
        return context.makeImage()
    }

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
        setId: TdInt64 = 2,
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
            setId: setId,
            sticker: TDLibFixtures.file(id: fileId, downloadedSize: 0),
            thumbnail: thumbnail,
            width: width,
        )
    }

    private func animation(fileId: Int, width: Int, height: Int) -> TDLibKit.Animation {
        TDLibKit.Animation(
            animation: TDLibFixtures.file(id: fileId, downloadedSize: 0),
            duration: 1,
            fileName: "animation.mp4",
            hasStickers: false,
            height: height,
            mimeType: "video/mp4",
            minithumbnail: nil,
            thumbnail: nil,
            width: width,
        )
    }
}
