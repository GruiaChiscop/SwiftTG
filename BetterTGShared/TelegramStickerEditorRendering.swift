// TelegramStickerEditorRendering.swift

import CoreImage

@MainActor enum TelegramStickerEditorRendering {
    static func pngData(
        sourceImage: CGImage,
        snapshot: TelegramMediaEditorSnapshot,
    ) throws -> Data {
        guard !snapshot.overlays.contains(where: { overlay in
            if case .sticker(let sticker) = overlay.content {
                sticker.format.isAnimated
            } else {
                false
            }
        }) else {
            throw TelegramStickerEditorError.animatedOverlayUnsupported
        }

        let canvasSize = CGSize(width: sourceImage.width, height: sourceImage.height)
        var composited = TelegramMediaEffectsRendering.apply(
            snapshot.effects,
            to: CIImage(cgImage: sourceImage),
        )
        if !snapshot.strokes.isEmpty || !snapshot.overlays.isEmpty {
            let overlayImage = try TelegramGifCompositor.renderOverlay(
                snapshot: .init(strokes: snapshot.strokes, overlays: snapshot.overlays),
                canvasSize: canvasSize,
            )
            composited = CIImage(cgImage: overlayImage)
                .composited(over: composited)
                .cropped(to: composited.extent)
        }
        let cropped = TelegramMediaCropRendering.apply(snapshot.crop, to: composited, canvasSize: canvasSize)
        guard let rendered = CIContext().createCGImage(cropped, from: cropped.extent),
              let telegramSized = TelegramStickerCropRendering.renderedCropImage(
                  source: rendered,
                  normalizedCropRect: CGRect(x: 0, y: 0, width: 1, height: 1),
              ),
              let data = TelegramStickerCropRendering.pngData(from: telegramSized)
        else {
            throw TelegramStickerEditorError.renderingFailed
        }
        return data
    }
}
