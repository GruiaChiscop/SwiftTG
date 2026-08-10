// TelegramGifCompositor.swift

import AVFoundation
import CoreImage
import ImageIO
import SwiftUI

@MainActor enum TelegramGifCompositor {
    // MARK: Internal

    static func export(
        asset: AVAsset,
        snapshot: TelegramMediaEditorSnapshot,
        canvasSize: CGSize,
        timeRange: CMTimeRange,
        outputURL: URL,
    ) async throws {
        let hasEdits = !snapshot.strokes.isEmpty || !snapshot.overlays.isEmpty || !snapshot.effects.isIdentity
        let preset = hasEdits ? AVAssetExportPresetHighestQuality : AVAssetExportPresetPassthrough
        guard let exporter = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw TelegramGifEditorError.exportUnavailable
        }

        if hasEdits {
            let resources = try await compositionResources(snapshot: snapshot, canvasSize: canvasSize)
            exporter.videoComposition = try await AVVideoComposition.videoComposition(with: asset) { request in
                let effectedSource = TelegramMediaEffectsRendering.apply(
                    snapshot.effects,
                    to: request.sourceImage,
                )
                guard let coreImageOverlay = resources.overlayImage(
                    for: snapshot.overlays,
                    at: request.compositionTime.seconds,
                ) else {
                    request.finish(with: effectedSource, context: nil)
                    return
                }
                let sourceExtent = request.sourceImage.extent
                let scale = CGAffineTransform(
                    scaleX: sourceExtent.width / coreImageOverlay.extent.width,
                    y: sourceExtent.height / coreImageOverlay.extent.height,
                )
                let translation = CGAffineTransform(
                    translationX: sourceExtent.minX,
                    y: sourceExtent.minY,
                )
                let positionedOverlay = coreImageOverlay
                    .transformed(by: scale)
                    .transformed(by: translation)
                let output = positionedOverlay
                    .composited(over: effectedSource)
                    .cropped(to: sourceExtent)
                request.finish(with: output, context: nil)
            }
        }

        exporter.timeRange = timeRange
        try await exporter.export(to: outputURL, as: .mp4)
    }

    static func renderOverlay(
        snapshot: TelegramMediaEditorSnapshot,
        canvasSize: CGSize,
    ) throws -> CGImage {
        guard canvasSize.width > 0, canvasSize.height > 0 else {
            throw TelegramGifEditorError.overlayRenderingFailed
        }
        let stickerImages = try loadStickerImages(from: snapshot.overlays)
        let renderer = ImageRenderer(content: TelegramExportOverlayView(
            snapshot: snapshot,
            stickerImages: stickerImages,
        ))
        renderer.proposedSize = .init(canvasSize)
        renderer.scale = 1
        guard let image = renderer.cgImage else {
            throw TelegramGifEditorError.overlayRenderingFailed
        }
        return image
    }

    // MARK: Private

    private static func compositionResources(
        snapshot: TelegramMediaEditorSnapshot,
        canvasSize: CGSize,
    ) async throws -> TelegramGifCompositionResources {
        let animatedStickers = snapshot.overlays.compactMap { overlay -> TelegramStickerOverlay? in
            guard case .sticker(let sticker) = overlay.content, sticker.format.isAnimated else { return nil }
            return sticker
        }
        let animatedFrames = try await TelegramAnimatedStickerFrameLoader.load(
            stickers: animatedStickers,
            canvasSize: canvasSize,
        )
        let drawingLayer: CIImage? =
            if snapshot.strokes.isEmpty {
                nil
            } else {
                try CIImage(cgImage: renderOverlay(
                    snapshot: .init(strokes: snapshot.strokes, overlays: []),
                    canvasSize: canvasSize,
                ))
            }
        var staticLayers = [UUID: CIImage]()
        for overlay in snapshot.overlays {
            if case .sticker(let sticker) = overlay.content, sticker.format.isAnimated {
                continue
            }
            let image = try renderOverlay(
                snapshot: .init(strokes: [], overlays: [overlay]),
                canvasSize: canvasSize,
            )
            staticLayers[overlay.id] = CIImage(cgImage: image)
        }
        return TelegramGifCompositionResources(
            canvasSize: canvasSize,
            drawingLayer: drawingLayer,
            staticOverlayLayers: staticLayers,
            animatedFrames: animatedFrames,
        )
    }

    private static func loadStickerImages(
        from overlays: [TelegramMediaOverlay],
    ) throws -> [URL: CGImage] {
        let urls = Set(overlays.compactMap { overlay -> URL? in
            guard case .sticker(let sticker) = overlay.content, sticker.format == .staticImage else { return nil }
            return sticker.url
        })
        var images = [URL: CGImage]()
        for url in urls {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else {
                throw TelegramGifEditorError.stickerRenderingFailed
            }
            images[url] = image
        }
        return images
    }
}
