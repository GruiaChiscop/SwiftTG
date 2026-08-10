// TelegramGifCompositor.swift

import AVFoundation
import CoreImage
import CoreVideo
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
        if !snapshot.crop.isIdentity {
            try await exportTransformed(
                asset: asset,
                snapshot: snapshot,
                canvasSize: canvasSize,
                timeRange: timeRange,
                outputURL: outputURL,
            )
            return
        }

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
                let composited: CIImage
                if let coreImageOverlay = resources.overlayImage(
                    for: snapshot.overlays,
                    at: request.compositionTime.seconds,
                ) {
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
                    composited = positionedOverlay
                        .composited(over: effectedSource)
                        .cropped(to: sourceExtent)
                } else {
                    composited = effectedSource
                }
                request.finish(with: composited, context: nil)
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

    private static func exportTransformed(
        asset: AVAsset,
        snapshot: TelegramMediaEditorSnapshot,
        canvasSize: CGSize,
        timeRange: CMTimeRange,
        outputURL: URL,
    ) async throws {
        guard let assetURL = (asset as? AVURLAsset)?.url else {
            throw TelegramGifEditorError.exportUnavailable
        }
        let resources = try await compositionResources(snapshot: snapshot, canvasSize: canvasSize)
        let task = Task.detached {
            try await writeTransformedVideo(
                assetURL: assetURL,
                snapshot: snapshot,
                canvasSize: canvasSize,
                timeRange: timeRange,
                outputURL: outputURL,
                resources: resources,
            )
        }
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private nonisolated static func writeTransformedVideo(
        assetURL: URL,
        snapshot: TelegramMediaEditorSnapshot,
        canvasSize: CGSize,
        timeRange: CMTimeRange,
        outputURL: URL,
        resources: TelegramGifCompositionResources,
    ) async throws {
        let asset = AVURLAsset(url: assetURL)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw TelegramGifEditorError.exportUnavailable
        }
        let preferredTransform = try await track.load(.preferredTransform)
        let outputSize = TelegramMediaCropRendering.outputSize(snapshot.crop, canvasSize: canvasSize)
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = timeRange
        let readerOutput = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            ],
        )
        readerOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(readerOutput) else {
            throw TelegramGifEditorError.exportUnavailable
        }
        reader.add(readerOutput)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let writerInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(outputSize.width),
                AVVideoHeightKey: Int(outputSize.height),
            ],
        )
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(outputSize.width),
                kCVPixelBufferHeightKey as String: Int(outputSize.height),
            ],
        )
        guard writer.canAdd(writerInput) else {
            throw TelegramGifEditorError.exportUnavailable
        }
        writer.add(writerInput)
        guard writer.startWriting(), reader.startReading() else {
            throw writer.error ?? reader.error ?? TelegramGifEditorError.exportUnavailable
        }
        writer.startSession(atSourceTime: .zero)

        do {
            let context = CIContext()
            while let sampleBuffer = readerOutput.copyNextSampleBuffer() {
                try Task.checkCancellation()
                try await waitUntilReady(writerInput, writer: writer)
                guard let sourceBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
                      let pool = adaptor.pixelBufferPool
                else {
                    throw TelegramGifEditorError.exportUnavailable
                }
                var optionalOutputBuffer: CVPixelBuffer?
                guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &optionalOutputBuffer) == kCVReturnSuccess,
                      let outputBuffer = optionalOutputBuffer
                else {
                    throw TelegramGifEditorError.exportUnavailable
                }
                let sourcePresentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                let presentationTime = sourcePresentationTime - timeRange.start
                let frame = renderedFrame(
                    sourceBuffer: sourceBuffer,
                    presentationTime: sourcePresentationTime.seconds,
                    preferredTransform: preferredTransform,
                    snapshot: snapshot,
                    canvasSize: canvasSize,
                    resources: resources,
                )
                context.render(
                    frame,
                    to: outputBuffer,
                    bounds: CGRect(origin: .zero, size: outputSize),
                    colorSpace: CGColorSpaceCreateDeviceRGB(),
                )
                guard adaptor.append(outputBuffer, withPresentationTime: presentationTime) else {
                    throw writer.error ?? TelegramGifEditorError.exportUnavailable
                }
            }
            guard reader.status == .completed else {
                throw reader.error ?? TelegramGifEditorError.exportUnavailable
            }
            writerInput.markAsFinished()
            await writer.finishWriting()
            guard writer.status == .completed else {
                throw writer.error ?? TelegramGifEditorError.exportUnavailable
            }
        } catch {
            reader.cancelReading()
            writer.cancelWriting()
            throw error
        }
    }

    private nonisolated static func renderedFrame(
        sourceBuffer: CVPixelBuffer,
        presentationTime: Double,
        preferredTransform: CGAffineTransform,
        snapshot: TelegramMediaEditorSnapshot,
        canvasSize: CGSize,
        resources: TelegramGifCompositionResources,
    ) -> CIImage {
        let transformedSource = CIImage(cvPixelBuffer: sourceBuffer).transformed(by: preferredTransform)
        let source = transformedSource.transformed(by: CGAffineTransform(
            translationX: -transformedSource.extent.minX,
            y: -transformedSource.extent.minY,
        ))
        let effectedSource = TelegramMediaEffectsRendering.apply(snapshot.effects, to: source)
        let composited: CIImage
        if let overlay = resources.overlayImage(for: snapshot.overlays, at: presentationTime) {
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
        return TelegramMediaCropRendering.apply(snapshot.crop, to: composited, canvasSize: canvasSize)
    }

    private nonisolated static func waitUntilReady(
        _ input: AVAssetWriterInput,
        writer: AVAssetWriter,
    ) async throws {
        while !input.isReadyForMoreMediaData {
            try Task.checkCancellation()
            guard writer.status == .writing else {
                throw writer.error ?? TelegramGifEditorError.exportUnavailable
            }
            try await Task.sleep(for: .milliseconds(2))
        }
    }

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
