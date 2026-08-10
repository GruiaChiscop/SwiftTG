// TelegramGifEditorError.swift

import Foundation

// MARK: - TelegramGifEditorError

enum TelegramGifEditorError: LocalizedError {
    case downloadFailed
    case exportUnavailable
    case invalidDuration

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .downloadFailed:
            "The GIF couldn't be downloaded for editing."
        case .exportUnavailable:
            "This GIF can't be edited on this device."
        case .invalidDuration:
            "This GIF is too short to edit."
        }
    }
}
