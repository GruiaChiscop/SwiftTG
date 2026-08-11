// TelegramStickerVideoRendering.swift

import CoreImage
import Foundation
import TelegramWebM

@MainActor enum TelegramStickerVideoRendering {
    // MARK: Internal

    struct Metadata: Equatable, Sendable {
        let duration: Double
        let frameRate: Int
        let height: Int
        let width: Int
    }

    nonisolated static func requiresVideo(
        source: TelegramStickerEditorSource,
        snapshot: TelegramMediaEditorSnapshot,
    ) -> Bool {
        source.isAnimated || snapshot.overlays.contains { overlay in
            guard case .sticker(let sticker) = overlay.content else { return false }
            return sticker.format.isAnimated
        }
    }

    static func export(
        source: TelegramStickerEditorSource,
        snapshot: TelegramMediaEditorSnapshot,
        outputURL: URL,
    ) async throws -> Metadata {
        let canvasSize = source.canvasSize
        let resources = try await TelegramGifCompositor.compositionResources(
            snapshot: snapshot,
            canvasSize: canvasSize,
        )
        let duration = outputDuration(source: source, resources: resources)
        let frameRate = outputFrameRate(source: source, resources: resources)
        let outputSize = outputSize(crop: snapshot.crop, canvasSize: canvasSize)
        let metadata = Metadata(
            duration: duration,
            frameRate: frameRate,
            height: Int(outputSize.height),
            width: Int(outputSize.width),
        )

        do {
            try await exportConcurrently(
                source: source,
                snapshot: snapshot,
                canvasSize: canvasSize,
                resources: resources,
                metadata: metadata,
                outputURL: outputURL,
            )
            return metadata
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw TelegramStickerEditorError.videoRenderingFailed
        }
    }

    nonisolated static func outputSize(crop: TelegramMediaCrop, canvasSize: CGSize) -> CGSize {
        let croppedSize = TelegramMediaCropRendering.outputSize(crop, canvasSize: canvasSize)
        guard croppedSize.width > 0, croppedSize.height > 0 else {
            return CGSize(
                width: TelegramStickerCropRendering.outputSide,
                height: TelegramStickerCropRendering.outputSide,
            )
        }
        let scale = Double(TelegramStickerCropRendering.outputSide) / max(croppedSize.width, croppedSize.height)
        return CGSize(
            width: evenDimension(croppedSize.width * scale),
            height: evenDimension(croppedSize.height * scale),
        )
    }

    // MARK: Private

    private static let maximumDuration = 3.0
    private static let maximumFrameRate = 30

    @concurrent private nonisolated static func exportConcurrently(
        source: TelegramStickerEditorSource,
        snapshot: TelegramMediaEditorSnapshot,
        canvasSize: CGSize,
        resources: TelegramGifCompositionResources,
        metadata: Metadata,
        outputURL: URL,
    ) async throws {
        let encoder = try WebMEncoder(
            outputURL: outputURL,
            width: metadata.width,
            height: metadata.height,
            frameRate: metadata.frameRate,
        )
        let context = CIContext()
        let frameCount = max(1, Int((metadata.duration * Double(metadata.frameRate)).rounded(.up)))
        let outputRect = CGRect(x: 0, y: 0, width: metadata.width, height: metadata.height)

        for index in 0..<frameCount {
            try Task.checkCancellation()
            let time = Double(index) / Double(metadata.frameRate)
            guard let sourceImage = source.image(at: time) else {
                throw TelegramStickerEditorError.videoRenderingFailed
            }
            let frame = renderedFrame(
                sourceImage: sourceImage,
                time: time,
                snapshot: snapshot,
                canvasSize: canvasSize,
                resources: resources,
                outputSize: outputRect.size,
            )
            guard let image = context.createCGImage(frame, from: outputRect) else {
                throw TelegramStickerEditorError.videoRenderingFailed
            }
            try encoder.append(image)
        }
        try Task.checkCancellation()
        try encoder.finish()
    }

    private nonisolated static func renderedFrame(
        sourceImage: CGImage,
        time: Double,
        snapshot: TelegramMediaEditorSnapshot,
        canvasSize: CGSize,
        resources: TelegramGifCompositionResources,
        outputSize: CGSize,
    ) -> CIImage {
        let source = CIImage(cgImage: sourceImage)
        let effectedSource = TelegramMediaEffectsRendering.apply(snapshot.effects, to: source)
        let composited: CIImage
        if let overlay = resources.overlayImage(for: snapshot.overlays, at: time) {
            let scale = CGAffineTransform(
                scaleX: source.extent.width / overlay.extent.width,
                y: source.extent.height / overlay.extent.height,
            )
            composited = overlay
                .transformed(by: scale)
                .composited(over: effectedSource)
                .cropped(to: source.extent)
        } else {
            composited = effectedSource
        }
        let cropped = TelegramMediaCropRendering.apply(snapshot.crop, to: composited, canvasSize: canvasSize)
        let normalized = cropped.transformed(by: CGAffineTransform(
            translationX: -cropped.extent.minX,
            y: -cropped.extent.minY,
        ))
        return normalized
            .transformed(by: CGAffineTransform(
                scaleX: outputSize.width / normalized.extent.width,
                y: outputSize.height / normalized.extent.height,
            ))
            .cropped(to: CGRect(origin: .zero, size: outputSize))
    }

    private static func outputDuration(
        source: TelegramStickerEditorSource,
        resources: TelegramGifCompositionResources,
    ) -> Double {
        let overlayDuration = resources.animatedFrames.values.map(\.duration).max() ?? 0
        return min(max(source.duration, overlayDuration, 1.0 / Double(maximumFrameRate)), maximumDuration)
    }

    private static func outputFrameRate(
        source: TelegramStickerEditorSource,
        resources: TelegramGifCompositionResources,
    ) -> Int {
        let overlayFrameRate = resources.animatedFrames.values.map(\.frameRate).max() ?? 0
        return min(maximumFrameRate, max(1, Int(max(source.frameRate, overlayFrameRate).rounded())))
    }

    private nonisolated static func evenDimension(_ value: Double) -> Double {
        max(2, min(512, (value / 2).rounded(.down) * 2))
    }
}
