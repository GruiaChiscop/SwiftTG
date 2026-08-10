// TelegramMediaCropRendering.swift

import CoreGraphics
import CoreImage

enum TelegramMediaCropRendering {
    // MARK: Internal

    static func normalizedCropRect(_ crop: TelegramMediaCrop, canvasSize: CGSize) -> CGRect {
        let rotatedSize = crop.rotatedCanvasSize(for: canvasSize)
        let aspectRatio =
            switch crop.aspectRatio {
            case .original:
                rotatedSize.width / rotatedSize.height
            case .square:
                1.0
            }
        return TelegramStickerCropRendering.normalizedCropRect(
            imageSize: rotatedSize,
            aspectRatio: aspectRatio,
            zoom: crop.zoom,
            offset: CGSize(width: crop.horizontalOffset, height: crop.verticalOffset),
        )
    }

    static func outputSize(_ crop: TelegramMediaCrop, canvasSize: CGSize) -> CGSize {
        let rotatedSize = crop.rotatedCanvasSize(for: canvasSize)
        let baseCrop = TelegramStickerCropRendering.normalizedCropRect(
            imageSize: rotatedSize,
            aspectRatio: crop.aspectRatio == .square ? 1 : rotatedSize.width / rotatedSize.height,
            zoom: 1,
            offset: .zero,
        )
        return evenSize(CGSize(
            width: rotatedSize.width * baseCrop.width,
            height: rotatedSize.height * baseCrop.height,
        ))
    }

    static func apply(_ crop: TelegramMediaCrop, to source: CIImage, canvasSize: CGSize) -> CIImage {
        let normalizedSource = source.transformed(by: CGAffineTransform(
            translationX: -source.extent.minX,
            y: -source.extent.minY,
        ))
        let rotated = rotate(normalizedSource, quarterTurns: crop.normalizedQuarterTurns)
        let transformed = crop.isMirrored ? rotated.oriented(.upMirrored) : rotated
        let normalized = transformed.transformed(by: CGAffineTransform(
            translationX: -transformed.extent.minX,
            y: -transformed.extent.minY,
        ))
        let normalizedRect = normalizedCropRect(crop, canvasSize: canvasSize)
        let cropRect = CGRect(
            x: normalized.extent.width * normalizedRect.minX,
            y: normalized.extent.height * (1 - normalizedRect.maxY),
            width: normalized.extent.width * normalizedRect.width,
            height: normalized.extent.height * normalizedRect.height,
        ).intersection(normalized.extent)
        guard !cropRect.isEmpty else { return normalized }

        let outputSize = outputSize(crop, canvasSize: canvasSize)
        let translated = normalized
            .cropped(to: cropRect)
            .transformed(by: CGAffineTransform(translationX: -cropRect.minX, y: -cropRect.minY))
        let scaled = translated.transformed(by: CGAffineTransform(
            scaleX: outputSize.width / cropRect.width,
            y: outputSize.height / cropRect.height,
        ))
        return scaled.cropped(to: CGRect(origin: .zero, size: outputSize))
    }

    // MARK: Private

    private static func rotate(_ image: CIImage, quarterTurns: Int) -> CIImage {
        switch quarterTurns {
        case 1: image.oriented(.left)
        case 2: image.oriented(.down)
        case 3: image.oriented(.right)
        default: image
        }
    }

    private static func evenSize(_ size: CGSize) -> CGSize {
        CGSize(
            width: max(2, (size.width / 2).rounded(.down) * 2),
            height: max(2, (size.height / 2).rounded(.down) * 2),
        )
    }
}
