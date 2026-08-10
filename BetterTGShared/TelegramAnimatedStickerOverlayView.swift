// TelegramAnimatedStickerOverlayView.swift

import SwiftUI

struct TelegramAnimatedStickerOverlayView: View {
    // MARK: Internal

    let sticker: TelegramStickerOverlay
    let overlay: TelegramMediaOverlay
    let canvasSize: CGSize
    let shouldPlay: Bool
    let isSelected: Bool

    var body: some View {
        Group {
            switch sticker.format {
            case .tgs:
                TelegramStickerAnimationView(
                    fileURL: sticker.url,
                    renderSize: stickerSize,
                    shouldPlay: shouldPlay,
                )
            case .webm:
                TelegramStickerVideoView(fileURL: sticker.url, shouldPlay: shouldPlay)
            case .webp:
                Color.clear
            }
        }
        .frame(width: stickerSize.width, height: stickerSize.height)
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.tint, lineWidth: 2)
                    .padding(-4)
            }
        }
        .scaleEffect(overlay.scale)
        .rotationEffect(.degrees(overlay.rotationDegrees))
    }

    // MARK: Private

    private var stickerSize: CGSize {
        TelegramMediaOverlayLayout.stickerSize(sticker, canvasSize: canvasSize)
    }
}
