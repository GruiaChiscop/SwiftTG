// TelegramAnimatedStickerFrameLoader.swift

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
            let frames = try loadFrames(for: sticker, renderSize: renderSize)
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
    ) throws -> TelegramAnimatedStickerFrameSet {
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
        case .webp:
            throw TelegramGifEditorError.animatedStickerRenderingFailed
        }
    }
}
