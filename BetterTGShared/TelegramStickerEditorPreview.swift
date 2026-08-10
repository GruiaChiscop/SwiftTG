// TelegramStickerEditorPreview.swift

import SwiftUI

struct TelegramStickerEditorPreview: View {
    // MARK: Internal

    let sourceImage: CGImage

    @Bindable var editorState: TelegramMediaEditorState

    var body: some View {
        TelegramMediaCropPreview(crop: editorState.crop, canvasSize: canvasSize) {
            ZStack {
                Image(decorative: sourceImage, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .brightness(editorState.effects.brightness)
                    .contrast(editorState.effects.contrast)
                    .saturation(editorState.effects.saturation)
                    .blur(radius: editorState.effects.blurRadius)
                TelegramDrawingCanvas(editorState: editorState)
                TelegramOverlayCanvas(currentTime: 0, editorState: editorState)
            }
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .frame(minHeight: 180, maxHeight: 360)
        .background(.black)
        .clipShape(.rect(cornerRadius: 12))
        .overlay {
            if editorState.tool == .crop {
                TelegramCropGestureOverlay(editorState: editorState)
            }
        }
        .accessibilityLabel("Sticker editor preview")
    }

    // MARK: Private

    private var canvasSize: CGSize {
        CGSize(width: sourceImage.width, height: sourceImage.height)
    }

    private var aspectRatio: Double {
        let outputSize = TelegramMediaCropRendering.outputSize(editorState.crop, canvasSize: canvasSize)
        guard outputSize.width > 0, outputSize.height > 0 else { return 1 }
        return outputSize.width / outputSize.height
    }
}
