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
        let hasArtwork = !snapshot.strokes.isEmpty || !snapshot.overlays.isEmpty
        let preset = hasArtwork ? AVAssetExportPresetHighestQuality : AVAssetExportPresetPassthrough
        guard let exporter = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw TelegramGifEditorError.exportUnavailable
        }

        if hasArtwork {
            let overlayImage = try renderOverlay(snapshot: snapshot, canvasSize: canvasSize)
            let coreImageOverlay = CIImage(cgImage: overlayImage)
            exporter.videoComposition = try await AVVideoComposition.videoComposition(with: asset) { request in
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
                    .composited(over: request.sourceImage)
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

    private static func loadStickerImages(
        from overlays: [TelegramMediaOverlay],
    ) throws -> [URL: CGImage] {
        let urls = Set(overlays.compactMap { overlay -> URL? in
            guard case .sticker(let sticker) = overlay.content else { return nil }
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
