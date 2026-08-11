// TelegramStickerEditorOutput.swift

import Foundation
import TDLibKit

enum TelegramStickerEditorOutput: Sendable {
    case image(Data)
    case video(fileURL: URL, width: Int, height: Int, duration: Double)

    // MARK: Internal

    var format: StickerFormat {
        switch self {
        case .image: .stickerFormatWebp
        case .video: .stickerFormatWebm
        }
    }
}
