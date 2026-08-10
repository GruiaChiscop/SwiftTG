// TelegramStickerOverlay.swift

import Foundation

struct TelegramStickerOverlay: Equatable, Sendable {
    let url: URL
    let pixelWidth: Int
    let pixelHeight: Int
    let format: TelegramStickerOverlayFormat
}
