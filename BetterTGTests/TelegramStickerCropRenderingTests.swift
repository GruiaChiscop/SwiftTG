// TelegramStickerCropRenderingTests.swift

@testable import BetterTG
import CoreGraphics
import Foundation
import ImageIO
import Testing

struct TelegramStickerCropRenderingTests {
    // MARK: Internal

    @Test func `square aspect ratio at zoom 1 fits the shorter side and stays centered`() throws {
        let imageSize = CGSize(width: 400, height: 200)
        let rect = TelegramStickerCropRendering.normalizedCropRect(
            imageSize: imageSize,
            aspectRatio: 1,
            zoom: 1,
            offset: .zero,
        )
        // `rect` is normalized against each axis' own (different) absolute size, so a truly square
        // crop does NOT have equal normalized width/height on a non-square image - it has equal
        // normalized width/height only once denormalized back to pixels. 200px wide / 400px image
        // width = 0.5; 200px tall / 200px image height = 1.0. Both describe the same 200x200 crop.
        #expect(abs(rect.width - 0.5) < 0.0001) // 200/400
        #expect(abs(rect.height - 1) < 0.0001) // 200/200
        #expect(abs(rect.midX - 0.5) < 0.0001)
        #expect(abs(rect.midY - 0.5) < 0.0001)

        // Denormalized back to actual pixels, the crop must be genuinely square.
        let cropRectInPixels = CGRect(
            x: rect.minX * imageSize.width,
            y: rect.minY * imageSize.height,
            width: rect.width * imageSize.width,
            height: rect.height * imageSize.height,
        )
        #expect(abs(cropRectInPixels.width - cropRectInPixels.height) < 0.0001)

        let source = try #require(Self.solidColorImage(size: imageSize))
        let cropped = try #require(TelegramStickerCropRendering.renderedCropImage(
            source: source,
            normalizedCropRect: rect,
        ))
        #expect(cropped.width == TelegramStickerCropRendering.outputSide)
        #expect(cropped.height == TelegramStickerCropRendering.outputSide)
    }

    @Test func `original aspect ratio matches the source image and covers it fully at zoom 1`() {
        let imageSize = CGSize(width: 400, height: 200)
        let rect = TelegramStickerCropRendering.normalizedCropRect(
            imageSize: imageSize,
            aspectRatio: imageSize.width / imageSize.height,
            zoom: 1,
            offset: .zero,
        )
        #expect(abs(rect.width - 1) < 0.0001)
        #expect(abs(rect.height - 1) < 0.0001)
    }

    @Test func `crop rect shrinks as zoom increases and keeps the requested aspect ratio`() {
        let rect = TelegramStickerCropRendering.normalizedCropRect(
            imageSize: CGSize(width: 300, height: 300),
            aspectRatio: 1,
            zoom: 3,
            offset: .zero,
        )
        #expect(rect.width == rect.height)
        #expect(abs(rect.width - 1.0 / 3) < 0.0001)
    }

    @Test func `crop rect offset stays within image bounds at the pan limit`() {
        let rect = TelegramStickerCropRendering.normalizedCropRect(
            imageSize: CGSize(width: 400, height: 200),
            aspectRatio: 1,
            zoom: 1,
            offset: CGSize(width: 1, height: 1),
        )
        #expect(rect.minX >= -0.0001)
        #expect(rect.maxX <= 1.0001)
        #expect(rect.minY >= -0.0001)
        #expect(rect.maxY <= 1.0001)
    }

    @Test func `square crop always renders exactly 512x512 regardless of source aspect ratio`() throws {
        for size in [CGSize(width: 800, height: 600), CGSize(width: 100, height: 300), CGSize(
            width: 512,
            height: 512,
        )] {
            let source = try #require(Self.solidColorImage(size: size))
            let cropRect = TelegramStickerCropRendering.normalizedCropRect(
                imageSize: size,
                aspectRatio: 1,
                zoom: 1,
                offset: .zero,
            )
            let cropped = try #require(TelegramStickerCropRendering.renderedCropImage(
                source: source,
                normalizedCropRect: cropRect,
            ))
            #expect(cropped.width == TelegramStickerCropRendering.outputSide)
            #expect(cropped.height == TelegramStickerCropRendering.outputSide)
        }
    }

    @Test func `rectangular crop puts exactly 512 on the longer side, per Telegram's own requirement`() throws {
        // core.telegram.org/stickers: "one side must be exactly 512 pixels - the other side can be
        // 512 pixels or less" - a landscape source should render wide (512 wide, shorter tall), and
        // a portrait source should render tall (512 tall, shorter wide).
        let landscapeSize = CGSize(width: 1600, height: 900) // 16:9
        let landscapeSource = try #require(Self.solidColorImage(size: landscapeSize))
        let landscapeCropRect = TelegramStickerCropRendering.normalizedCropRect(
            imageSize: landscapeSize,
            aspectRatio: landscapeSize.width / landscapeSize.height,
            zoom: 1,
            offset: .zero,
        )
        let landscapeCropped = try #require(TelegramStickerCropRendering.renderedCropImage(
            source: landscapeSource,
            normalizedCropRect: landscapeCropRect,
        ))
        #expect(landscapeCropped.width == TelegramStickerCropRendering.outputSide)
        #expect(landscapeCropped.height < TelegramStickerCropRendering.outputSide)

        let portraitSize = CGSize(width: 900, height: 1600) // 9:16
        let portraitSource = try #require(Self.solidColorImage(size: portraitSize))
        let portraitCropRect = TelegramStickerCropRendering.normalizedCropRect(
            imageSize: portraitSize,
            aspectRatio: portraitSize.width / portraitSize.height,
            zoom: 1,
            offset: .zero,
        )
        let portraitCropped = try #require(TelegramStickerCropRendering.renderedCropImage(
            source: portraitSource,
            normalizedCropRect: portraitCropRect,
        ))
        #expect(portraitCropped.height == TelegramStickerCropRendering.outputSide)
        #expect(portraitCropped.width < TelegramStickerCropRendering.outputSide)
    }

    @Test func `PNG round trip decodes back to the same dimensions`() throws {
        let source = try #require(Self.solidColorImage(size: CGSize(width: 640, height: 480)))
        let cropRect = TelegramStickerCropRendering.normalizedCropRect(
            imageSize: CGSize(width: 640, height: 480),
            aspectRatio: 1,
            zoom: 1,
            offset: .zero,
        )
        let cropped = try #require(TelegramStickerCropRendering.renderedCropImage(
            source: source,
            normalizedCropRect: cropRect,
        ))
        let pngData = try #require(TelegramStickerCropRendering.pngData(from: cropped))

        let decodedSource = try #require(CGImageSourceCreateWithData(pngData as CFData, nil))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(decodedSource, 0, nil))
        #expect(decoded.width == cropped.width)
        #expect(decoded.height == cropped.height)
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
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
