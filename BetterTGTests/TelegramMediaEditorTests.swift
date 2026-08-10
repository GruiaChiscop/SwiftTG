// TelegramMediaEditorTests.swift

import AVFoundation
@testable import BetterTG
import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import Testing

// MARK: - TelegramMediaEditorTests

@MainActor struct TelegramMediaEditorTests {
    // MARK: Internal

    @Test func `overlay transform is one undo step and can be redone`() throws {
        let state = TelegramMediaEditorState()
        state.addText("BetterTG")
        let overlayID = try #require(state.selectedOverlayID)

        state.beginInteraction()
        state.moveSelected(to: .init(x: 0.2, y: 0.8))
        state.scaleSelected(to: 1.75)
        state.rotateSelected(to: 42)
        state.endInteraction()

        #expect(state.selectedOverlay?.position == .init(x: 0.2, y: 0.8))
        #expect(state.selectedOverlay?.scale == 1.75)
        #expect(state.selectedOverlay?.rotationDegrees == 42)

        state.undo()
        #expect(state.selectedOverlay?.id == overlayID)
        #expect(state.selectedOverlay?.position == .init(x: 0.5, y: 0.5))
        #expect(state.selectedOverlay?.scale == 1)
        #expect(state.selectedOverlay?.rotationDegrees == 0)

        state.redo()
        #expect(state.selectedOverlay?.position == .init(x: 0.2, y: 0.8))
        #expect(state.selectedOverlay?.scale == 1.75)
        #expect(state.selectedOverlay?.rotationDegrees == 42)
    }

    @Test func `drawing and overlay mutations preserve history order`() {
        let state = TelegramMediaEditorState()
        state.brushWidth = 0.025
        state.addStroke(points: [.init(x: 0.1, y: 0.2), .init(x: 0.9, y: 0.8)])
        state.addEmoji("🎨")
        state.duplicateSelected()

        #expect(state.strokes.count == 1)
        #expect(state.strokes.first?.width == 0.025)
        #expect(state.overlays.count == 2)

        state.undo()
        #expect(state.overlays.count == 1)
        state.undo()
        #expect(state.overlays.isEmpty)
        state.undo()
        #expect(state.strokes.isEmpty)
    }

    @Test func `overlay positions and transforms are clamped to supported bounds`() {
        let state = TelegramMediaEditorState()
        state.addText("Bounds")
        state.moveSelected(to: .init(x: -2, y: 3))
        state.scaleSelected(to: 20)
        state.rotateSelected(to: -500)

        #expect(state.selectedOverlay?.position == .init(x: 0, y: 1))
        #expect(state.selectedOverlay?.scale == 4)
        #expect(state.selectedOverlay?.rotationDegrees == -180)
    }

    @Test func `timeline visibility is undoable and uses inclusive bounds`() {
        let state = TelegramMediaEditorState()
        state.timelineDuration = 3
        state.addText("Timed")
        state.beginInteraction()
        state.setSelectedStartTime(0.8)
        state.setSelectedEndTime(1.6)
        state.endInteraction()

        #expect(state.selectedOverlay?.isVisible(at: 0.79) == false)
        #expect(state.selectedOverlay?.isVisible(at: 0.8) == true)
        #expect(state.selectedOverlay?.isVisible(at: 1.6) == true)
        #expect(state.selectedOverlay?.isVisible(at: 1.61) == false)

        state.undo()
        #expect(state.selectedOverlay?.startTime == 0)
        #expect(state.selectedOverlay?.endTime == 3)
    }

    @Test func `animated sticker loader decodes TGS and WebM frames`() async throws {
        let tgsURL = try TelegramMediaEditorFixtures.tgsURL()
        let webmURL = try TelegramMediaEditorFixtures.webmURL()
        defer {
            try? FileManager.default.removeItem(at: tgsURL)
            try? FileManager.default.removeItem(at: webmURL)
        }
        let stickers = [
            TelegramStickerOverlay(url: tgsURL, pixelWidth: 100, pixelHeight: 100, format: .tgs),
            TelegramStickerOverlay(url: webmURL, pixelWidth: 32, pixelHeight: 32, format: .webm),
        ]

        let frames = try await TelegramAnimatedStickerFrameLoader.load(
            stickers: stickers,
            canvasSize: CGSize(width: 64, height: 64),
        )

        #expect(frames[tgsURL]?.images.count == 30)
        #expect(frames[tgsURL]?.frameRate == 30)
        #expect(frames[webmURL]?.images.count == 2)
        #expect(frames[webmURL]?.frameRate == 4)
        let firstTgsFrame = try #require(frames[tgsURL]?.images.first)
        #expect(try Self.brightPixelCount(in: firstTgsFrame) > 0)
    }

    @Test func `drawing renderer produces transparent and painted pixels`() throws {
        let snapshot = TelegramMediaEditorSnapshot(
            strokes: [.init(
                points: [.init(x: 0.1, y: 0.5), .init(x: 0.9, y: 0.5)],
                color: .white,
                width: 0.12,
            )],
            overlays: [],
        )
        let image = try TelegramGifCompositor.renderOverlay(
            snapshot: snapshot,
            canvasSize: CGSize(width: 64, height: 64),
        )

        let center = try Self.pixel(in: image, x: 32, y: 32)
        let corner = try Self.pixel(in: image, x: 2, y: 2)
        #expect(center.alpha > 200)
        #expect(center.red > 200)
        #expect(corner.alpha == 0)
    }

    @Test func `brush styles change opacity and footprint`() throws {
        let points = [TelegramEditorPoint(x: 0.1, y: 0.5), TelegramEditorPoint(x: 0.9, y: 0.5)]
        let pen = try TelegramGifCompositor.renderOverlay(
            snapshot: .init(
                strokes: [.init(points: points, color: .white, width: 0.02, style: .pen)],
                overlays: [],
            ),
            canvasSize: CGSize(width: 64, height: 64),
        )
        let highlighter = try TelegramGifCompositor.renderOverlay(
            snapshot: .init(
                strokes: [.init(points: points, color: .white, width: 0.02, style: .highlighter)],
                overlays: [],
            ),
            canvasSize: CGSize(width: 64, height: 64),
        )
        let neon = try TelegramGifCompositor.renderOverlay(
            snapshot: .init(
                strokes: [.init(points: points, color: .white, width: 0.02, style: .neon)],
                overlays: [],
            ),
            canvasSize: CGSize(width: 64, height: 64),
        )

        #expect(try Self.pixel(in: highlighter, x: 32, y: 32).alpha < Self.pixel(in: pen, x: 32, y: 32).alpha)
        #expect(try Self.visiblePixelCount(in: neon) > Self.visiblePixelCount(in: pen))
    }

    @Test func `effect adjustments participate in undo redo and reset`() {
        let state = TelegramMediaEditorState()
        state.beginInteraction()
        state.effects.brightness = 0.25
        state.effects.contrast = 1.4
        state.endInteraction()

        #expect(state.effects.brightness == 0.25)
        #expect(state.effects.contrast == 1.4)
        state.undo()
        #expect(state.effects.isIdentity)
        state.redo()
        #expect(state.effects.brightness == 0.25)
        state.resetEffects()
        #expect(state.effects.isIdentity)
        state.undo()
        #expect(state.effects.brightness == 0.25)
    }

    @Test func `Core Image effects brighten a dark frame`() throws {
        let source = CIImage(color: CIColor(red: 0.1, green: 0.1, blue: 0.1))
            .cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))
        let effects = TelegramMediaEffects(brightness: 0.4, contrast: 1, saturation: 1, blurRadius: 0)
        let output = TelegramMediaEffectsRendering.apply(effects, to: source)
        let rendered = try #require(CIContext().createCGImage(output, from: output.extent))

        #expect(try Self.pixel(in: rendered, x: 4, y: 4).red > 80)
    }

    @Test func `export compositor paints the first and last video frames`() async throws {
        let sourceURL = Self.temporaryURL(label: "source")
        let outputURL = Self.temporaryURL(label: "output")
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
            try? FileManager.default.removeItem(at: outputURL)
        }

        try await Self.writeBlackVideo(to: sourceURL)
        let snapshot = TelegramMediaEditorSnapshot(
            strokes: [.init(
                points: [.init(x: 0.1, y: 0.5), .init(x: 0.9, y: 0.5)],
                color: .white,
                width: 0.15,
            )],
            overlays: [],
        )
        try await TelegramGifCompositor.export(
            asset: AVURLAsset(url: sourceURL),
            snapshot: snapshot,
            canvasSize: CGSize(width: 64, height: 64),
            timeRange: CMTimeRange(start: .zero, duration: CMTime(value: 3, timescale: 10)),
            outputURL: outputURL,
        )

        let asset = AVURLAsset(url: outputURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let firstFrame = try await generator.image(at: CMTime(value: 1, timescale: 20)).image
        let lastFrame = try await generator.image(at: CMTime(value: 5, timescale: 20)).image
        let firstCenter = try Self.pixel(in: firstFrame, x: 32, y: 32)
        let lastCenter = try Self.pixel(in: lastFrame, x: 32, y: 32)

        #expect(firstCenter.red > 180)
        #expect(firstCenter.green > 180)
        #expect(firstCenter.blue > 180)
        #expect(lastCenter.red > 180)
        #expect(lastCenter.green > 180)
        #expect(lastCenter.blue > 180)
    }

    @Test func `animated overlay export respects its timeline interval`() async throws {
        let sourceURL = Self.temporaryURL(label: "animated-source")
        let outputURL = Self.temporaryURL(label: "animated-output")
        let tgsURL = try TelegramMediaEditorFixtures.tgsURL()
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
            try? FileManager.default.removeItem(at: outputURL)
            try? FileManager.default.removeItem(at: tgsURL)
        }
        try await Self.writeBlackVideo(to: sourceURL)
        let sticker = TelegramStickerOverlay(
            url: tgsURL,
            pixelWidth: 100,
            pixelHeight: 100,
            format: .tgs,
        )
        let overlay = TelegramMediaOverlay(
            content: .sticker(sticker),
            scale: 2,
            startTime: 0.075,
            endTime: 0.175,
        )
        try await TelegramGifCompositor.export(
            asset: AVURLAsset(url: sourceURL),
            snapshot: .init(strokes: [], overlays: [overlay]),
            canvasSize: CGSize(width: 64, height: 64),
            timeRange: CMTimeRange(start: .zero, duration: CMTime(value: 3, timescale: 10)),
            outputURL: outputURL,
        )

        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: outputURL))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let first = try await generator.image(at: .zero).image
        let middle = try await generator.image(at: CMTime(value: 1, timescale: 10)).image
        let last = try await generator.image(at: CMTime(value: 2, timescale: 10)).image

        #expect(try Self.brightPixelCount(in: first) == 0)
        #expect(try Self.brightPixelCount(in: middle) > 0)
        #expect(try Self.brightPixelCount(in: last) == 0)
    }

    @Test func `video export applies effects without overlays`() async throws {
        let sourceURL = Self.temporaryURL(label: "effects-source")
        let outputURL = Self.temporaryURL(label: "effects-output")
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
            try? FileManager.default.removeItem(at: outputURL)
        }
        try await Self.writeBlackVideo(to: sourceURL)
        try await TelegramGifCompositor.export(
            asset: AVURLAsset(url: sourceURL),
            snapshot: .init(
                strokes: [],
                overlays: [],
                effects: .init(brightness: 0.5, contrast: 1, saturation: 1, blurRadius: 0),
            ),
            canvasSize: CGSize(width: 64, height: 64),
            timeRange: CMTimeRange(start: .zero, duration: CMTime(value: 3, timescale: 10)),
            outputURL: outputURL,
        )

        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: outputURL))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let frame = try await generator.image(at: CMTime(value: 1, timescale: 10)).image
        #expect(try Self.pixel(in: frame, x: 32, y: 32).red > 80)
    }

    // MARK: Private

    private static let videoSide = 64

    private static func temporaryURL(label: String) -> URL {
        URL.temporaryDirectory.appending(path: "bettertg-editor-test-\(label)-\(UUID().uuidString).mp4")
    }

    private static func writeBlackVideo(to url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: videoSide,
                AVVideoHeightKey: videoSide,
            ],
        )
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: videoSide,
                kCVPixelBufferHeightKey as String: videoSide,
            ],
        )
        guard writer.canAdd(input) else {
            throw TelegramMediaEditorTestError.writerInputRejected
        }
        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? TelegramMediaEditorTestError.writerFailed
        }
        writer.startSession(atSourceTime: .zero)

        for frameIndex in 0..<3 {
            try await waitUntilReady(input, writer: writer)
            guard let pool = adaptor.pixelBufferPool else {
                throw TelegramMediaEditorTestError.writerNotReady
            }
            var optionalBuffer: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &optionalBuffer) == kCVReturnSuccess,
                  let buffer = optionalBuffer
            else {
                throw TelegramMediaEditorTestError.pixelBufferCreationFailed
            }
            Self.fillBlack(buffer)
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frameIndex), timescale: 10))
            else {
                throw writer.error ?? TelegramMediaEditorTestError.writerFailed
            }
        }

        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw writer.error ?? TelegramMediaEditorTestError.writerFailed
        }
    }

    private static func waitUntilReady(
        _ input: AVAssetWriterInput,
        writer: AVAssetWriter,
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !input.isReadyForMoreMediaData {
            try Task.checkCancellation()
            switch writer.status {
            case .failed:
                throw writer.error ?? TelegramMediaEditorTestError.writerFailed
            case .cancelled, .completed:
                throw writer.error ?? TelegramMediaEditorTestError.writerNotReady
            case .unknown, .writing:
                break
            @unknown default:
                throw TelegramMediaEditorTestError.writerNotReady
            }
            guard ContinuousClock.now < deadline else {
                throw TelegramMediaEditorTestError.writerNotReady
            }
            await Task.yield()
        }
    }

    private static func fillBlack(_ buffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else { return }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        for y in 0..<videoSide {
            let row = baseAddress.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
            for x in 0..<videoSide {
                let offset = x * 4
                row[offset] = 0
                row[offset + 1] = 0
                row[offset + 2] = 0
                row[offset + 3] = 255
            }
        }
    }

    private static func pixel(in image: CGImage, x: Int, y: Int) throws -> TelegramMediaEditorPixel {
        let data = try rgbaData(from: image)
        let offset = (y * image.width + x) * 4
        return TelegramMediaEditorPixel(
            red: data[offset],
            green: data[offset + 1],
            blue: data[offset + 2],
            alpha: data[offset + 3],
        )
    }

    private static func brightPixelCount(in image: CGImage) throws -> Int {
        let data = try rgbaData(from: image)
        return stride(from: 0, to: data.count, by: 4).count { offset in
            data[offset] > 30 || data[offset + 1] > 30 || data[offset + 2] > 30
        }
    }

    private static func visiblePixelCount(in image: CGImage) throws -> Int {
        let data = try rgbaData(from: image)
        return stride(from: 3, to: data.count, by: 4).count { data[$0] > 0 }
    }

    private static func rgbaData(from image: CGImage) throws -> [UInt8] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        guard let context = CGContext(
            data: &data,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ) else {
            throw TelegramMediaEditorTestError.imageContextCreationFailed
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return data
    }
}
