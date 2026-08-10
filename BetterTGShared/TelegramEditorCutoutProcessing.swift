// TelegramEditorCutoutProcessing.swift

import CoreGraphics
import Foundation
import ImageIO

enum TelegramEditorCutoutProcessing {
    // MARK: Internal

    @concurrent static func overlay(from photoData: Data) async throws -> TelegramStickerOverlay {
        try Task.checkCancellation()
        guard let sourceImage = decodedImage(from: photoData) else {
            throw TelegramGifEditorError.invalidCutoutImage
        }
        let cutoutImage = try TelegramStickerBackgroundRemoval.removingBackground(from: sourceImage)
        try Task.checkCancellation()
        return try temporaryOverlay(from: cutoutImage)
    }

    static func temporaryOverlay(
        from cutoutImage: CGImage,
        directory: URL = .temporaryDirectory,
    ) throws -> TelegramStickerOverlay {
        guard let pngData = TelegramStickerCropRendering.pngData(from: cutoutImage) else {
            throw TelegramGifEditorError.cutoutProcessingFailed
        }
        let url = directory.appending(path: "bettertg-cutout-\(UUID().uuidString).png")
        do {
            try pngData.write(to: url, options: .atomic)
        } catch {
            throw TelegramGifEditorError.cutoutProcessingFailed
        }
        return TelegramStickerOverlay(
            url: url,
            pixelWidth: cutoutImage.width,
            pixelHeight: cutoutImage.height,
            format: .staticImage,
            kind: .cutout,
        )
    }

    // MARK: Private

    private static let maximumPixelSize = 1536

    private static func decodedImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
