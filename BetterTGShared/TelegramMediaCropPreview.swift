// TelegramMediaCropPreview.swift

import SwiftUI

struct TelegramMediaCropPreview<Content: View>: View {
    let crop: TelegramMediaCrop
    let canvasSize: CGSize
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            let cropRect = TelegramMediaCropRendering.normalizedCropRect(crop, canvasSize: canvasSize)
            let rotatedWidth = proxy.size.width / cropRect.width
            let rotatedHeight = proxy.size.height / cropRect.height
            let originalSize = crop.normalizedQuarterTurns.isMultiple(of: 2)
                ? CGSize(width: rotatedWidth, height: rotatedHeight)
                : CGSize(width: rotatedHeight, height: rotatedWidth)

            content()
                .frame(width: originalSize.width, height: originalSize.height)
                .rotationEffect(.degrees(Double(crop.normalizedQuarterTurns) * -90))
                .frame(width: rotatedWidth, height: rotatedHeight)
                .scaleEffect(x: crop.isMirrored ? -1 : 1, y: 1)
                .offset(
                    x: -cropRect.minX * rotatedWidth,
                    y: -cropRect.minY * rotatedHeight,
                )
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .clipped()
    }
}
