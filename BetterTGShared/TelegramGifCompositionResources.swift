// TelegramGifCompositionResources.swift

import CoreImage

struct TelegramGifCompositionResources: Sendable {
    // MARK: Internal

    let canvasSize: CGSize
    let drawingLayer: CIImage?
    let staticOverlayLayers: [UUID: CIImage]
    let animatedFrames: [URL: TelegramAnimatedStickerFrameSet]

    func overlayImage(
        for overlays: [TelegramMediaOverlay],
        at time: Double,
    ) -> CIImage? {
        var result = drawingLayer
        for overlay in overlays where overlay.isVisible(at: time) {
            let layer: CIImage? =
                if case .sticker(let sticker) = overlay.content, sticker.format.isAnimated {
                    animatedLayer(sticker: sticker, overlay: overlay, time: time)
                } else {
                    staticOverlayLayers[overlay.id]
                }
            guard let layer else { continue }
            result =
                if let result {
                    layer.composited(over: result)
                } else {
                    layer
                }
        }
        return result
    }

    // MARK: Private

    private func animatedLayer(
        sticker: TelegramStickerOverlay,
        overlay: TelegramMediaOverlay,
        time: Double,
    ) -> CIImage? {
        guard let image = animatedFrames[sticker.url]?.image(at: time - overlay.startTime) else { return nil }
        let layoutSize = TelegramMediaOverlayLayout.stickerSize(sticker, canvasSize: canvasSize)
        let center = CGPoint(
            x: overlay.position.x * canvasSize.width,
            y: (1 - overlay.position.y) * canvasSize.height,
        )
        return CIImage(cgImage: image)
            .transformed(by: .init(
                scaleX: layoutSize.width / Double(image.width),
                y: layoutSize.height / Double(image.height),
            ))
            .transformed(by: .init(
                translationX: -layoutSize.width / 2,
                y: -layoutSize.height / 2,
            ))
            .transformed(by: .init(scaleX: overlay.scale, y: overlay.scale))
            .transformed(by: .init(rotationAngle: overlay.rotationDegrees * .pi / 180))
            .transformed(by: .init(translationX: center.x, y: center.y))
    }
}
