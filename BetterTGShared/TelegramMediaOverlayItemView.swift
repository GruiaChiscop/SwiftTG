// TelegramMediaOverlayItemView.swift

import ImageIO
import SwiftUI

struct TelegramMediaOverlayItemView: View {
    // MARK: Internal

    let overlay: TelegramMediaOverlay
    let canvasSize: CGSize
    let shouldPlay: Bool

    @Bindable var editorState: TelegramMediaEditorState

    var body: some View {
        Button(action: select) {
            TelegramMediaOverlayContentView(
                overlay: overlay,
                canvasSize: canvasSize,
                stickerImage: stickerImage,
                shouldPlay: shouldPlay,
                isSelected: editorState.selectedOverlayID == overlay.id,
            )
        }
        .buttonStyle(.plain)
        .position(
            x: overlay.position.x * canvasSize.width,
            y: overlay.position.y * canvasSize.height,
        )
        .simultaneousGesture(transformGesture)
        .task(id: stickerURL) { loadStickerImage() }
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: Private

    @State private var interactionOrigin: TelegramMediaOverlay?
    @State private var stickerImage: CGImage?

    private var accessibilityLabel: String {
        switch overlay.content {
        case .text(let text): "Text overlay, \(text)"
        case .emoji(let emoji): "Emoji overlay, \(emoji)"
        case .sticker(let sticker):
            sticker.kind == .cutout ? "Cutout overlay" : "Sticker overlay"
        }
    }

    private var stickerURL: URL? {
        guard case .sticker(let sticker) = overlay.content, sticker.format == .staticImage else { return nil }
        return sticker.url
    }

    private var transformGesture: some Gesture {
        SimultaneousGesture(
            DragGesture(minimumDistance: 1),
            SimultaneousGesture(MagnifyGesture(), RotateGesture()),
        )
        .onChanged { value in
            if interactionOrigin == nil {
                editorState.select(overlay.id)
                editorState.beginInteraction()
                interactionOrigin = overlay
            }
            guard let interactionOrigin else { return }
            if let drag = value.first, canvasSize.width > 0, canvasSize.height > 0 {
                editorState.moveSelected(to: .init(
                    x: interactionOrigin.position.x + drag.translation.width / canvasSize.width,
                    y: interactionOrigin.position.y + drag.translation.height / canvasSize.height,
                ))
            }
            if let magnification = value.second?.first {
                editorState.scaleSelected(to: interactionOrigin.scale * magnification.magnification)
            }
            if let rotation = value.second?.second {
                editorState.rotateSelected(
                    to: interactionOrigin.rotationDegrees + rotation.rotation.degrees,
                )
            }
        }
        .onEnded { _ in
            editorState.endInteraction()
            interactionOrigin = nil
        }
    }

    private func select() {
        editorState.select(overlay.id)
    }

    private func loadStickerImage() {
        guard let stickerURL,
              let source = CGImageSourceCreateWithURL(stickerURL as CFURL, nil)
        else {
            stickerImage = nil
            return
        }
        stickerImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
