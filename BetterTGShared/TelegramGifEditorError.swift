// TelegramGifEditorError.swift

import Foundation

// MARK: - TelegramGifEditorError

enum TelegramGifEditorError: LocalizedError {
    case downloadFailed
    case animatedStickerRenderingFailed
    case cutoutProcessingFailed
    case exportUnavailable
    case invalidCutoutImage
    case invalidDuration
    case overlayRenderingFailed
    case stickerRenderingFailed

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .animatedStickerRenderingFailed:
            "An animated sticker couldn't be rendered."
        case .cutoutProcessingFailed:
            "The subject couldn't be prepared as an overlay."
        case .downloadFailed:
            "The GIF couldn't be downloaded for editing."
        case .exportUnavailable:
            "This GIF can't be edited on this device."
        case .invalidDuration:
            "This GIF is too short to edit."
        case .invalidCutoutImage:
            "The selected photo couldn't be opened."
        case .overlayRenderingFailed:
            "The drawing and overlays couldn't be rendered."
        case .stickerRenderingFailed:
            "One of the sticker overlays couldn't be rendered."
        }
    }
}
