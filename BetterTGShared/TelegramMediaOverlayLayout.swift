// TelegramMediaOverlayLayout.swift

import CoreGraphics

enum TelegramMediaOverlayLayout {
    static func stickerSize(_ sticker: TelegramStickerOverlay, canvasSize: CGSize) -> CGSize {
        let side = min(canvasSize.width, canvasSize.height) * 0.3
        guard sticker.pixelWidth > 0, sticker.pixelHeight > 0 else {
            return CGSize(width: side, height: side)
        }
        return CGSize(
            width: side * min(Double(sticker.pixelWidth) / Double(sticker.pixelHeight), 1),
            height: side * min(Double(sticker.pixelHeight) / Double(sticker.pixelWidth), 1),
        )
    }
}
