// TelegramEditorCutoutTests.swift

@testable import BetterTG
import CoreGraphics
import CoreImage
import Foundation
import Testing

@MainActor struct TelegramEditorCutoutTests {
    // MARK: Internal

    @Test func `foreground mask preserves subject and clears background`() throws {
        let image = try Self.halfMaskedImage()

        let subjectPixel = try Self.pixel(in: image, x: 1, y: 2)
        let backgroundPixel = try Self.pixel(in: image, x: 6, y: 2)
        #expect(subjectPixel.red > 240)
        #expect(subjectPixel.alpha > 240)
        #expect(backgroundPixel.alpha == 0)
    }

    @Test func `temporary cutout is a transparent static overlay`() throws {
        let image = try Self.halfMaskedImage()
        let overlay = try TelegramEditorCutoutProcessing.temporaryOverlay(from: image)
        defer { try? FileManager.default.removeItem(at: overlay.url) }

        #expect(overlay.kind == .cutout)
        #expect(overlay.format == .staticImage)
        #expect(overlay.pixelWidth == 8)
        #expect(overlay.pixelHeight == 4)
        #expect(FileManager.default.fileExists(atPath: overlay.url.path))

        let rendered = try TelegramGifCompositor.renderOverlay(
            snapshot: .init(
                strokes: [],
                overlays: [.init(content: .sticker(overlay), scale: 3)],
            ),
            canvasSize: CGSize(width: 64, height: 64),
        )
        #expect(try Self.pixel(in: rendered, x: 24, y: 32).alpha > 200)
        #expect(try Self.pixel(in: rendered, x: 40, y: 32).alpha == 0)
    }

    @Test func `cutout participates in editor history`() throws {
        let overlay = try TelegramEditorCutoutProcessing.temporaryOverlay(from: Self.halfMaskedImage())
        defer { try? FileManager.default.removeItem(at: overlay.url) }
        let state = TelegramMediaEditorState()

        state.addSticker(overlay)
        guard case .sticker(let selectedCutout) = state.selectedOverlay?.content else {
            Issue.record("The cutout wasn't selected after insertion.")
            return
        }
        #expect(selectedCutout.kind == .cutout)
        state.undo()
        #expect(state.overlays.isEmpty)
        state.redo()
        #expect(state.overlays.count == 1)
    }

    // MARK: Private

    private static let extent = CGRect(x: 0, y: 0, width: 8, height: 4)

    private static func halfMaskedImage() throws -> CGImage {
        let source = CIImage(color: CIColor(red: 1, green: 0, blue: 0))
            .cropped(to: extent)
        let blackMask = CIImage(color: CIColor(red: 0, green: 0, blue: 0))
            .cropped(to: extent)
        let whiteHalf = CIImage(color: CIColor(red: 1, green: 1, blue: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: 4, height: 4))
        let mask = whiteHalf.composited(over: blackMask)
        return try TelegramStickerBackgroundRemoval.applyingMask(mask, to: source)
    }

    private static func pixel(
        in image: CGImage,
        x: Int,
        y: Int,
    ) throws -> (red: UInt8, alpha: UInt8) {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        guard let context = CGContext(
            data: &data,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ) else {
            throw TelegramGifEditorError.overlayRenderingFailed
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let offset = (y * image.width + x) * 4
        return (data[offset], data[offset + 3])
    }
}
