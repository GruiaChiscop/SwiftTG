// TelegramMediaOverlayArtwork.swift

import SwiftUI

struct TelegramMediaOverlayArtwork: View {
    // MARK: Internal

    let overlay: TelegramMediaOverlay
    let canvasSize: CGSize
    let stickerImage: CGImage?
    var isSelected = false

    var body: some View {
        Group {
            switch overlay.content {
            case .text(let text):
                Text(text)
                    .font(.system(size: max(18, min(canvasSize.width, canvasSize.height) * 0.085), weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 1)
                    .frame(maxWidth: canvasSize.width * 0.75)
                    .padding(6)
            case .emoji(let emoji):
                Text(emoji)
                    .font(.system(size: max(40, min(canvasSize.width, canvasSize.height) * 0.22)))
                    .padding(4)
            case .sticker(let sticker):
                if sticker.format.isAnimated {
                    Color.clear
                        .frame(width: stickerSize(sticker).width, height: stickerSize(sticker).height)
                } else if let stickerImage {
                    Image(decorative: stickerImage, scale: 1)
                        .resizable()
                        .scaledToFit()
                        .frame(width: stickerSize(sticker).width, height: stickerSize(sticker).height)
                } else {
                    ProgressView()
                        .frame(width: stickerSize(sticker).width, height: stickerSize(sticker).height)
                }
            }
        }
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

    private func stickerSize(_ sticker: TelegramStickerOverlay) -> CGSize {
        TelegramMediaOverlayLayout.stickerSize(sticker, canvasSize: canvasSize)
    }
}
