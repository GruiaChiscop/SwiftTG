// TelegramCutoutMaskRendering.swift

import CoreGraphics
import CoreImage

enum TelegramCutoutMaskRendering {
    // MARK: Internal

    static func renderedCutout(
        document: TelegramCutoutDocument,
        strokes: [TelegramCutoutMaskStroke],
    ) throws -> CGImage {
        let mask = try renderedMask(document: document, strokes: strokes)
        return try TelegramStickerBackgroundRemoval.applyingMask(
            CIImage(cgImage: mask),
            to: CIImage(cgImage: document.sourceImage),
        )
    }

    static func renderedMask(
        document: TelegramCutoutDocument,
        strokes: [TelegramCutoutMaskStroke],
    ) throws -> CGImage {
        let width = document.sourceImage.width
        let height = document.sourceImage.height
        guard width > 0, height > 0,
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
              )
        else {
            throw TelegramStickerBackgroundRemoval.Error.renderingFailed
        }

        let size = CGSize(width: width, height: height)
        context.interpolationQuality = .high
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        context.draw(document.initialMask, in: CGRect(origin: .zero, size: size))

        for stroke in strokes {
            draw(stroke, in: context, size: size)
        }
        guard let image = context.makeImage() else {
            throw TelegramStickerBackgroundRemoval.Error.renderingFailed
        }
        return image
    }

    // MARK: Private

    private static func draw(
        _ stroke: TelegramCutoutMaskStroke,
        in context: CGContext,
        size: CGSize,
    ) {
        guard let first = stroke.points.first else { return }
        let lineWidth = max(1, stroke.width * min(size.width, size.height))
        context.saveGState()
        defer { context.restoreGState() }
        context.setBlendMode(stroke.mode == .erase ? .clear : .normal)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.setStrokeColor(CGColor(gray: 1, alpha: 1))
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setLineWidth(lineWidth)

        let firstPoint = CGPoint(x: first.x * size.width, y: first.y * size.height)
        if stroke.points.count == 1 {
            context.fillEllipse(in: CGRect(
                x: firstPoint.x - lineWidth / 2,
                y: firstPoint.y - lineWidth / 2,
                width: lineWidth,
                height: lineWidth,
            ))
            return
        }

        context.beginPath()
        context.move(to: firstPoint)
        for point in stroke.points.dropFirst() {
            context.addLine(to: CGPoint(x: point.x * size.width, y: point.y * size.height))
        }
        context.strokePath()
    }
}
