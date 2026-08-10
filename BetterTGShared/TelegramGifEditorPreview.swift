// TelegramGifEditorPreview.swift

import AVKit
import SwiftUI
import TDLibKit

struct TelegramGifEditorPreview: View {
    // MARK: Internal

    let animation: TDLibKit.Animation
    let player: AVPlayer?

    @Bindable var editorState: TelegramMediaEditorState

    var body: some View {
        Group {
            if let player {
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
                .aspectRatio(aspectRatio, contentMode: .fit)
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
        guard animation.width > 0, animation.height > 0 else { return 1 }
        return Double(animation.width) / Double(animation.height)
    }
}
