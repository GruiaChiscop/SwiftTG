// TelegramDrawingArtwork.swift

import SwiftUI

struct TelegramDrawingArtwork: View {
    // MARK: Internal

    let strokes: [TelegramDrawingStroke]
    let activePoints: [TelegramEditorPoint]
    let activeColor: TelegramEditorColor
    let activeWidth: Double

    var body: some View {
        Canvas { context, size in
            for stroke in strokes {
                draw(
                    points: stroke.points,
                    color: stroke.color.color,
                    width: stroke.width,
                    in: &context,
                    size: size,
                )
            }
            draw(
                points: activePoints,
                color: activeColor.color,
                width: activeWidth,
                in: &context,
                size: size,
            )
        }
        .accessibilityHidden(true)
    }

    // MARK: Private

    private func draw(
        points: [TelegramEditorPoint],
        color: Color,
        width: Double,
        in context: inout GraphicsContext,
        size: CGSize,
    ) {
        guard let first = points.first else { return }
        let lineWidth = max(1, width * min(size.width, size.height))
        if points.count == 1 {
            let center = CGPoint(x: first.x * size.width, y: first.y * size.height)
            let rect = CGRect(
                x: center.x - lineWidth / 2,
                y: center.y - lineWidth / 2,
                width: lineWidth,
                height: lineWidth,
            )
            context.fill(Path(ellipseIn: rect), with: .color(color))
            return
        }

        var path = Path()
        path.move(to: CGPoint(x: first.x * size.width, y: first.y * size.height))
        for point in points.dropFirst() {
            path.addLine(to: CGPoint(x: point.x * size.width, y: point.y * size.height))
        }
        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round),
        )
    }
}
