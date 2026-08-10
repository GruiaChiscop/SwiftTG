// TelegramCutoutMaskArtwork.swift

import SwiftUI

struct TelegramCutoutMaskArtwork: View {
    // MARK: Internal

    let initialMask: CGImage
    let strokes: [TelegramCutoutMaskStroke]
    let activeStroke: TelegramCutoutMaskStroke?

    var body: some View {
        Canvas { context, size in
            context.draw(
                Image(decorative: initialMask, scale: 1),
                in: CGRect(origin: .zero, size: size),
            )
            for stroke in strokes {
                draw(stroke, in: &context, size: size)
            }
            if let activeStroke {
                draw(activeStroke, in: &context, size: size)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: Private

    private func draw(
        _ stroke: TelegramCutoutMaskStroke,
        in context: inout GraphicsContext,
        size: CGSize,
    ) {
        guard let first = stroke.points.first else { return }
        var strokeContext = context
        strokeContext.blendMode = stroke.mode == .erase ? .destinationOut : .normal
        let lineWidth = max(1, stroke.width * min(size.width, size.height))
        let firstPoint = CGPoint(x: first.x * size.width, y: first.y * size.height)
        if stroke.points.count == 1 {
            strokeContext.fill(
                Path(ellipseIn: CGRect(
                    x: firstPoint.x - lineWidth / 2,
                    y: firstPoint.y - lineWidth / 2,
                    width: lineWidth,
                    height: lineWidth,
                )),
                with: .color(.white),
            )
            return
        }

        var path = Path()
        path.move(to: firstPoint)
        for point in stroke.points.dropFirst() {
            path.addLine(to: CGPoint(x: point.x * size.width, y: point.y * size.height))
        }
        strokeContext.stroke(
            path,
            with: .color(.white),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round),
        )
    }
}
