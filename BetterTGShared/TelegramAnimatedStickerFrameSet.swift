// TelegramAnimatedStickerFrameSet.swift

import CoreGraphics

struct TelegramAnimatedStickerFrameSet: Sendable {
    let images: [CGImage]
    let frameRate: Double

    var duration: Double {
        Double(images.count) / max(1, frameRate)
    }

    func image(at time: Double) -> CGImage? {
        guard !images.isEmpty else { return nil }
        let frame = Int(max(0, time) * max(1, frameRate)) % images.count
        return images[frame]
    }
}
