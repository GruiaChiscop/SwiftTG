// TelegramStickerOverlay.swift

import Foundation

struct TelegramStickerOverlay: Equatable, Sendable {
    // MARK: Lifecycle

    init(
        url: URL,
        pixelWidth: Int,
        pixelHeight: Int,
        format: TelegramStickerOverlayFormat,
        kind: TelegramStickerOverlayKind = .sticker,
    ) {
        self.url = url
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.format = format
        self.kind = kind
    }

    // MARK: Internal

    let url: URL
    let pixelWidth: Int
    let pixelHeight: Int
    let format: TelegramStickerOverlayFormat
    let kind: TelegramStickerOverlayKind
}
