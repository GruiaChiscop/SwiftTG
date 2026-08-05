// TelegramStickerCropRendering.swift

import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Pure, cross-platform (no UIKit/AppKit) sticker crop math and rendering - uses CoreImage
/// directly, the same approach as `telegramQrCodeImage(for:)`, so this can live in `BetterTGShared`
/// and be exercised by plain unit tests without a simulator.
enum TelegramStickerCropRendering {
    /// Telegram's actual static-sticker size requirement (core.telegram.org/stickers): "one side
    /// must be exactly 512 pixels in size - the other side can be 512 pixels or less." A sticker is
    /// NOT required to be square - only `aspectRatio == 1` produces a square 512x512 result.
    static let outputSide = 512

    /// The pure crop-window math shared by the gesture-driven crop surface and its
    /// VoiceOver-adjustable equivalent - both just drive `aspectRatio`/`zoom`/`offset` and call
    /// this. `aspectRatio` is width/height of the desired crop shape (`1` for square, or the
    /// source image's own `width/height` for "Original", matching Telegram's own crop tool's
    /// Square/Original presets). `zoom` is `1...maxZoom` (1 = the crop window shows as much of the
    /// image as a rectangle of that shape can, i.e. fit to whichever axis is the limiting one);
    /// `offset` is `-1...1` per axis, `0` centered, `±1` panned all the way to one edge - the
    /// *available* pan range shrinks automatically as `zoom` increases, so callers never need to
    /// compute bounds themselves.
    static func normalizedCropRect(imageSize: CGSize, aspectRatio: CGFloat, zoom: CGFloat, offset: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, aspectRatio > 0 else { return .zero }
        let clampedZoom = max(zoom, 1)

        // The largest rectangle of `aspectRatio` (width/height) that fits inside imageSize.
        let fitWidth: CGFloat
        let fitHeight: CGFloat
        if imageSize.width / imageSize.height > aspectRatio {
            fitHeight = imageSize.height
            fitWidth = fitHeight * aspectRatio
        } else {
            fitWidth = imageSize.width
            fitHeight = fitWidth / aspectRatio
        }

        let width = fitWidth / clampedZoom
        let height = fitHeight / clampedZoom

        let maxCenterOffsetX = (imageSize.width - width) / 2
        let maxCenterOffsetY = (imageSize.height - height) / 2
        let clampedOffsetX = min(max(offset.width, -1), 1)
        let clampedOffsetY = min(max(offset.height, -1), 1)

        let centerX = imageSize.width / 2 + clampedOffsetX * maxCenterOffsetX
        let centerY = imageSize.height / 2 + clampedOffsetY * maxCenterOffsetY

        return CGRect(
            x: (centerX - width / 2) / imageSize.width,
            y: (centerY - height / 2) / imageSize.height,
            width: width / imageSize.width,
            height: height / imageSize.height,
        )
    }

    /// Renders `source` cropped to `normalizedCropRect` (a region expressed in 0...1 fractions of
    /// the source image's width/height, top-left origin), scaled so its longer side becomes
    /// exactly `outputSide` and the shorter side follows proportionally - satisfying Telegram's
    /// "one side exactly 512, other side 512 or less" requirement for any crop shape, not just
    /// square.
    static func renderedCropImage(source: CGImage, normalizedCropRect: CGRect) -> CGImage? {
        let width = CGFloat(source.width)
        let height = CGFloat(source.height)
        guard width > 0, height > 0 else { return nil }

        let ciImage = CIImage(cgImage: source)
        // CoreImage's coordinate space has its origin at the bottom-left, while the crop rect is
        // expressed top-left (matching how the crop UI reasons about the image) - flip the y axis
        // when denormalizing.
        let cropRectInPixels = CGRect(
            x: normalizedCropRect.minX * width,
            y: (1 - normalizedCropRect.maxY) * height,
            width: normalizedCropRect.width * width,
            height: normalizedCropRect.height * height,
        ).intersection(ciImage.extent)
        guard !cropRectInPixels.isEmpty else { return nil }

        let cropped = ciImage.cropped(to: cropRectInPixels)
        let scale = CGFloat(outputSide) / max(cropRectInPixels.width, cropRectInPixels.height)
        let translated = cropped.transformed(by: CGAffineTransform(
            translationX: -cropRectInPixels.minX,
            y: -cropRectInPixels.minY,
        ))
        let scaled = translated.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let outputWidth = (cropRectInPixels.width * scale).rounded()
        let outputHeight = (cropRectInPixels.height * scale).rounded()
        return CIContext().createCGImage(
            scaled,
            from: CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight),
        )
    }

    /// Matches Telegram's own crop tool (`TGPhotoCropController`'s Rotate tab): rotates the whole
    /// image 90 degrees counterclockwise.
    static func rotated90DegreesCounterclockwise(_ image: CGImage) -> CGImage? {
        let oriented = CIImage(cgImage: image).oriented(.left)
        return CIContext().createCGImage(oriented, from: oriented.extent)
    }

    /// Matches Telegram's own crop tool (`TGPhotoCropController`'s Mirror tab): flips the whole
    /// image horizontally.
    static func mirroredHorizontally(_ image: CGImage) -> CGImage? {
        let oriented = CIImage(cgImage: image).oriented(.upMirrored)
        return CIContext().createCGImage(oriented, from: oriented.extent)
    }

    /// PNG-encodes via `ImageIO` - PNG with an alpha channel is accepted by TDLib's
    /// `uploadStickerFile` for a WEBP-format sticker (the server converts it), so no WEBP encoder
    /// is needed.
    static func pngData(from image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil,
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
