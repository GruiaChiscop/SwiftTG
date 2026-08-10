// TelegramExportOverlayView.swift

import SwiftUI

struct TelegramExportOverlayView: View {
    // MARK: Internal

    let snapshot: TelegramMediaEditorSnapshot
    let stickerImages: [URL: CGImage]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                TelegramDrawingArtwork(
                    strokes: snapshot.strokes,
                    activePoints: [],
                    activeColor: .white,
                    activeWidth: 0,
                )
                ForEach(snapshot.overlays) { overlay in
                    TelegramMediaOverlayArtwork(
                        overlay: overlay,
                        canvasSize: proxy.size,
                        stickerImage: stickerImage(for: overlay),
                    )
                    .position(
                        x: overlay.position.x * proxy.size.width,
                        y: overlay.position.y * proxy.size.height,
                    )
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    // MARK: Private

    private func stickerImage(for overlay: TelegramMediaOverlay) -> CGImage? {
        guard case .sticker(let sticker) = overlay.content else { return nil }
        return stickerImages[sticker.url]
    }
}
