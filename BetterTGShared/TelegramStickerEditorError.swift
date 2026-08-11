// TelegramStickerEditorError.swift

import Foundation

enum TelegramStickerEditorError: LocalizedError {
    case downloadFailed
    case imageDecodingFailed
    case renderingFailed
    case videoRenderingFailed

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .downloadFailed:
            "The sticker couldn't be downloaded for editing."
        case .imageDecodingFailed:
            "The sticker image couldn't be opened."
        case .renderingFailed:
            "The edited sticker couldn't be rendered."
        case .videoRenderingFailed:
            "The animated sticker couldn't be rendered."
        }
    }
}
