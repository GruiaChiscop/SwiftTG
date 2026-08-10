// TelegramOverlayCanvas.swift

import SwiftUI

struct TelegramOverlayCanvas: View {
    let currentTime: Double

    @Bindable var editorState: TelegramMediaEditorState

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(editorState.overlays) { overlay in
                    TelegramMediaOverlayItemView(
                        overlay: overlay,
                        canvasSize: proxy.size,
                        shouldPlay: overlay.isVisible(at: currentTime),
                        editorState: editorState,
                    )
                    .opacity(overlay.isVisible(at: currentTime) ? 1 : 0)
                    .allowsHitTesting(overlay.isVisible(at: currentTime))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .allowsHitTesting(editorState.tool == .select)
    }
}
