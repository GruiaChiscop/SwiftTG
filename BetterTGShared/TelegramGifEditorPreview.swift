// TelegramGifEditorPreview.swift

import AVKit
import SwiftUI

struct TelegramGifEditorPreview: View {
    // MARK: Internal

    let player: AVPlayer?
    let canvasSize: CGSize

    @Bindable var editorState: TelegramMediaEditorState

    var body: some View {
        Group {
            if let player {
                TelegramMediaCropPreview(crop: editorState.crop, canvasSize: canvasSize) {
                    ZStack {
                        TelegramVideoEffectsPreview(player: player, effects: editorState.effects)
                        TelegramDrawingCanvas(editorState: editorState)
                        TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { _ in
                            TelegramOverlayCanvas(
                                currentTime: player.currentTime().seconds,
                                editorState: editorState,
                            )
                        }
                    }
                }
                .aspectRatio(aspectRatio, contentMode: .fit)
                .overlay {
                    if editorState.tool == .crop {
                        TelegramCropGestureOverlay(editorState: editorState)
                    }
                }
            } else {
                ProgressView("Loading GIF")
            }
        }
        .frame(minHeight: 180, maxHeight: 300)
        .background(.black)
        .clipShape(.rect(cornerRadius: 12))
        .accessibilityLabel("GIF editor preview")
    }

    // MARK: Private

    private var aspectRatio: Double {
        let outputSize = TelegramMediaCropRendering.outputSize(editorState.crop, canvasSize: canvasSize)
        guard outputSize.width > 0, outputSize.height > 0 else { return 1 }
        return outputSize.width / outputSize.height
    }
}
