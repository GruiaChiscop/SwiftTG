// TelegramAnimatedStickerFrameSet.swift

import CoreGraphics

struct TelegramAnimatedStickerFrameSet: Sendable {
    let images: [CGImage]
    let frameRate: Double

    func image(at time: Double) -> CGImage? {
        guard !images.isEmpty else { return nil }
        let frame = Int(max(0, time) * max(1, frameRate)) % images.count
        return images[frame]
    }
}
