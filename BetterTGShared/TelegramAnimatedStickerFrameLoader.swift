// TelegramAnimatedStickerFrameLoader.swift

import AVFoundation
import CoreGraphics
import Foundation
import RLottieKit
import TelegramWebM

enum TelegramAnimatedStickerFrameLoader {
    // MARK: Internal

    @concurrent static func load(
        stickers: [TelegramStickerOverlay],
        canvasSize: CGSize,
    ) async throws -> [URL: TelegramAnimatedStickerFrameSet] {
        var result = [URL: TelegramAnimatedStickerFrameSet]()
        for sticker in stickers where sticker.format.isAnimated && result[sticker.url] == nil {
            try Task.checkCancellation()
            let renderSize = boundedRenderSize(for: sticker, canvasSize: canvasSize)
            let frames = try await loadFrames(for: sticker, renderSize: renderSize)
            result[sticker.url] = frames
        }
        return result
    }

    // MARK: Private

    private static let maximumFrameCount = 600
    private static let maximumRenderSide = 320.0

    private static func boundedRenderSize(
        for sticker: TelegramStickerOverlay,
        canvasSize: CGSize,
    ) -> CGSize {
        let layoutSize = TelegramMediaOverlayLayout.stickerSize(sticker, canvasSize: canvasSize)
        let requestedScale = min(
            maximumRenderSide / max(layoutSize.width, layoutSize.height),
            2,
        )
        return CGSize(
            width: max(1, (layoutSize.width * requestedScale).rounded()),
            height: max(1, (layoutSize.height * requestedScale).rounded()),
        )
    }

    private static func loadFrames(
        for sticker: TelegramStickerOverlay,
        renderSize: CGSize,
    ) async throws -> TelegramAnimatedStickerFrameSet {
        switch sticker.format {
        case .tgs:
            guard let animation = LottieAnimation(tgsFileURL: sticker.url) else {
                throw TelegramGifEditorError.animatedStickerRenderingFailed
            }
            var images = [CGImage]()
            for index in 0..<min(animation.frameCount, maximumFrameCount) {
                try Task.checkCancellation()
                guard let image = animation.renderFrame(index: index, size: renderSize, scale: 1) else {
                    throw TelegramGifEditorError.animatedStickerRenderingFailed
                }
                images.append(image)
            }
            guard !images.isEmpty else {
                throw TelegramGifEditorError.animatedStickerRenderingFailed
            }
            return TelegramAnimatedStickerFrameSet(
                images: images,
                frameRate: Double(max(1, animation.frameRate)),
            )
        case .webm:
            let animation = try WebMAnimation(fileURL: sticker.url)
            let expectedCount = min(
                max(1, Int((animation.duration * animation.frameRate).rounded(.up)) + 1),
                maximumFrameCount,
            )
            var images = [CGImage]()
            for _ in 0..<expectedCount {
                try Task.checkCancellation()
                guard let image = animation.nextFrame() else { break }
                images.append(image)
            }
            guard !images.isEmpty else {
                throw TelegramGifEditorError.animatedStickerRenderingFailed
            }
            return TelegramAnimatedStickerFrameSet(
                images: images,
                frameRate: max(1, animation.frameRate),
            )
        case .video:
            return try await loadVideoFrames(from: sticker.url, renderSize: renderSize)
        case .staticImage:
            throw TelegramGifEditorError.animatedStickerRenderingFailed
        }
    }

    private static func loadVideoFrames(
        from url: URL,
        renderSize: CGSize,
    ) async throws -> TelegramAnimatedStickerFrameSet {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw TelegramGifEditorError.animatedStickerRenderingFailed
        }
        let duration = try await asset.load(.duration).seconds
        let nominalFrameRate = try await Double(track.load(.nominalFrameRate))
        guard duration.isFinite, duration > 0 else {
            throw TelegramGifEditorError.animatedStickerRenderingFailed
        }

        let frameRate = min(30, max(1, nominalFrameRate.isFinite ? nominalFrameRate : 30))
        let frameCount = min(maximumFrameCount, max(1, Int((duration * frameRate).rounded(.up))))
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = renderSize
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        var images = [CGImage]()
        images.reserveCapacity(frameCount)
        for index in 0..<frameCount {
            try Task.checkCancellation()
            let time = CMTime(seconds: Double(index) / frameRate, preferredTimescale: 600)
            let frame = try await generator.image(at: time).image
            images.append(frame)
        }
        guard !images.isEmpty else {
            throw TelegramGifEditorError.animatedStickerRenderingFailed
        }
        return TelegramAnimatedStickerFrameSet(images: images, frameRate: frameRate)
    }
}
