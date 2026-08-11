// TelegramStickerEditorSource.swift

import CoreGraphics

enum TelegramStickerEditorSource: Sendable {
    case animation(TelegramAnimatedStickerFrameSet)
    case image(CGImage)

    // MARK: Internal

    var canvasSize: CGSize {
        guard let image = image(at: 0) else { return CGSize(width: 512, height: 512) }
        return CGSize(width: image.width, height: image.height)
    }

    var duration: Double {
        switch self {
        case .animation(let frames): frames.duration
        case .image: 0
        }
    }

    var frameRate: Double {
        switch self {
        case .animation(let frames): frames.frameRate
        case .image: 0
        }
    }

    var isAnimated: Bool {
        if case .animation = self {
            true
        } else {
            false
        }
    }

    func image(at time: Double) -> CGImage? {
        switch self {
        case .animation(let frames): frames.image(at: time)
        case .image(let image): image
        }
    }
}
