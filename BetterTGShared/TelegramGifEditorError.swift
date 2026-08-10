// TelegramGifEditorError.swift

import Foundation

// MARK: - TelegramGifEditorError

enum TelegramGifEditorError: LocalizedError {
    case downloadFailed
    case exportUnavailable
    case invalidDuration
    case overlayRenderingFailed
    case stickerRenderingFailed

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .downloadFailed:
            "The GIF couldn't be downloaded for editing."
        case .exportUnavailable:
            "This GIF can't be edited on this device."
        case .invalidDuration:
            "This GIF is too short to edit."
        case .overlayRenderingFailed:
            "The drawing and overlays couldn't be rendered."
        case .stickerRenderingFailed:
            "One of the sticker overlays couldn't be rendered."
        }
    }
}
