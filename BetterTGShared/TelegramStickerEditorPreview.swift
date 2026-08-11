// TelegramStickerEditorPreview.swift

import SwiftUI

struct TelegramStickerEditorPreview: View {
    // MARK: Internal

    let source: TelegramStickerEditorSource

    @Bindable var editorState: TelegramMediaEditorState

    var body: some View {
        TelegramMediaCropPreview(crop: editorState.crop, canvasSize: canvasSize) {
            if hasAnimation {
                TimelineView(.animation(minimumInterval: 1.0 / previewFrameRate)) { context in
                    preview(at: timelineTime(for: context.date))
                }
            } else {
                preview(at: 0)
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
        .accessibilityLabel(hasAnimation ? "Animated sticker editor preview" : "Sticker editor preview")
    }

    // MARK: Private

    private var canvasSize: CGSize {
        source.canvasSize
    }

    private var hasAnimation: Bool {
        source.isAnimated || editorState.overlays.contains { overlay in
            guard case .sticker(let sticker) = overlay.content else { return false }
            return sticker.format.isAnimated
        }
    }

    private var previewDuration: Double {
        max(source.duration, editorState.timelineDuration, 0.5)
    }

    private var previewFrameRate: Double {
        min(30, max(15, source.frameRate))
    }

    private var aspectRatio: Double {
        let outputSize = TelegramMediaCropRendering.outputSize(editorState.crop, canvasSize: canvasSize)
        guard outputSize.width > 0, outputSize.height > 0 else { return 1 }
        return outputSize.width / outputSize.height
    }

    private func preview(at time: Double) -> some View {
        ZStack {
            if let image = source.image(at: time) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .brightness(editorState.effects.brightness)
                    .contrast(editorState.effects.contrast)
                    .saturation(editorState.effects.saturation)
                    .blur(radius: editorState.effects.blurRadius)
            }
            TelegramDrawingCanvas(editorState: editorState)
            TelegramOverlayCanvas(currentTime: time, editorState: editorState)
        }
    }

    private func timelineTime(for date: Date) -> Double {
        date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: previewDuration)
    }
}
