// TelegramMediaOverlayContentView.swift

import SwiftUI

struct TelegramMediaOverlayContentView: View {
    let overlay: TelegramMediaOverlay
    let canvasSize: CGSize
    let stickerImage: CGImage?
    let shouldPlay: Bool
    let isSelected: Bool

    var body: some View {
        if case .sticker(let sticker) = overlay.content, sticker.format.isAnimated {
            TelegramAnimatedStickerOverlayView(
                sticker: sticker,
                overlay: overlay,
                canvasSize: canvasSize,
                shouldPlay: shouldPlay,
                isSelected: isSelected,
            )
        } else {
            TelegramMediaOverlayArtwork(
                overlay: overlay,
                canvasSize: canvasSize,
                stickerImage: stickerImage,
                isSelected: isSelected,
            )
        }
    }
}
