// TelegramStickerEditorRendering.swift

import CoreImage

enum TelegramStickerEditorRendering {
    /// `renderOverlay` (behind `strokes`/`overlays`) uses SwiftUI's `ImageRenderer`, which is
    /// MainActor-only, so the overlay bitmap is produced here; the CoreImage compositing and PNG
    /// encode - the CPU-heavy part - is then offloaded, mirroring the video path's
    /// `@concurrent exportConcurrently`.
    @MainActor
    static func pngData(
        sourceImage: CGImage,
        snapshot: TelegramMediaEditorSnapshot,
    ) async throws -> Data {
        let canvasSize = CGSize(width: sourceImage.width, height: sourceImage.height)
        let overlayImage: CGImage? =
            if snapshot.strokes.isEmpty, snapshot.overlays.isEmpty {
                nil
            } else {
                try TelegramGifCompositor.renderOverlay(
                    snapshot: .init(strokes: snapshot.strokes, overlays: snapshot.overlays),
                    canvasSize: canvasSize,
                )
            }
        return try await encode(
            sourceImage: sourceImage,
            overlayImage: overlayImage,
            snapshot: snapshot,
            canvasSize: canvasSize,
        )
    }

    @concurrent
    private static func encode(
        sourceImage: CGImage,
        overlayImage: CGImage?,
        snapshot: TelegramMediaEditorSnapshot,
        canvasSize: CGSize,
    ) async throws -> Data {
        var composited = TelegramMediaEffectsRendering.apply(
            snapshot.effects,
            to: CIImage(cgImage: sourceImage),
        )
        if let overlayImage {
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
