// TelegramOverlayCanvas.swift

import SwiftUI

struct TelegramOverlayCanvas: View {
    @Bindable var editorState: TelegramMediaEditorState

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(editorState.overlays) { overlay in
                    TelegramMediaOverlayItemView(
                        overlay: overlay,
                        canvasSize: proxy.size,
                        editorState: editorState,
                    )
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .allowsHitTesting(editorState.tool == .select)
    }
}
