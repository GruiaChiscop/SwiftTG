// TelegramAnimatedStickerEditingTests.swift

@testable import BetterTG
import CoreGraphics
import Foundation
import Testing

@MainActor struct TelegramAnimatedStickerEditingTests {
    // MARK: Internal

    @Test func `animated sticker export produces a decodable VP9 WebM`() async throws {
        let first = try #require(Self.image(red: 1, alpha: 0.5))
        let second = try #require(Self.image(red: 0, alpha: 1))
        let source = TelegramStickerEditorSource.animation(.init(
            images: [first, second],
            frameRate: 4,
        ))
        let outputURL = URL.temporaryDirectory
            .appending(path: "bettertg-animated-sticker-test-\(UUID().uuidString)")
            .appendingPathExtension("webm")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let metadata = try await TelegramStickerVideoRendering.export(
            source: source,
            snapshot: .init(
                strokes: [.init(
                    points: [.init(x: 0.1, y: 0.5), .init(x: 0.9, y: 0.5)],
                    color: .white,
                    width: 0.15,
                )],
                overlays: [],
            ),
            outputURL: outputURL,
        )
        let decoded = try await TelegramAnimatedStickerFrameLoader.loadSource(.init(
            url: outputURL,
            pixelWidth: metadata.width,
            pixelHeight: metadata.height,
            format: .webm,
        ))

        #expect(metadata.width == 512)
        #expect(metadata.height == 512)
        #expect(metadata.duration == 0.5)
        #expect(metadata.frameRate == 4)
        #expect(decoded.images.count == 2)
        #expect(decoded.duration == 0.5)
        let firstDecodedFrame = try #require(decoded.images.first)
        #expect(try Self.greenValue(in: firstDecodedFrame, x: 256, y: 256) > 180)
    }

    // MARK: Private

    private static func image(red: CGFloat, alpha: CGFloat) -> CGImage? {
        let side = 32
        guard let context = CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ) else { return nil }
        context.setFillColor(red: red, green: 0.25, blue: 0.5, alpha: alpha)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        return context.makeImage()
    }

    private static func greenValue(in image: CGImage, x: Int, y: Int) throws -> UInt8 {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ) else {
            throw TelegramStickerEditorError.imageDecodingFailed
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return pixels[(y * image.width + x) * 4 + 1]
    }
}
