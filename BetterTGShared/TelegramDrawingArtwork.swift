// TelegramDrawingArtwork.swift

import SwiftUI

struct TelegramDrawingArtwork: View {
    // MARK: Internal

    let strokes: [TelegramDrawingStroke]
    let activePoints: [TelegramEditorPoint]
    let activeColor: TelegramEditorColor
    let activeWidth: Double
    let activeStyle: TelegramBrushStyle

    var body: some View {
        Canvas { context, size in
            for stroke in strokes {
                draw(
                    points: stroke.points,
                    color: stroke.color.color,
                    width: stroke.width,
                    style: stroke.style,
                    in: &context,
                    size: size,
                )
            }
            draw(
                points: activePoints,
                color: activeColor.color,
                width: activeWidth,
                style: activeStyle,
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
        style: TelegramBrushStyle,
        in context: inout GraphicsContext,
        size: CGSize,
    ) {
        guard let first = points.first else { return }
        let lineWidth = max(1, width * style.widthMultiplier * min(size.width, size.height))
        if points.count == 1 {
            let center = CGPoint(x: first.x * size.width, y: first.y * size.height)
            let rect = CGRect(
                x: center.x - lineWidth / 2,
                y: center.y - lineWidth / 2,
                width: lineWidth,
                height: lineWidth,
            )
            if style == .neon {
                var glowContext = context
                glowContext.opacity = 0.35
                glowContext.fill(
                    Path(ellipseIn: rect.insetBy(dx: -lineWidth, dy: -lineWidth)),
                    with: .color(color),
                )
            }
            var styledContext = context
            styledContext.opacity = style.opacity
            styledContext.fill(Path(ellipseIn: rect), with: .color(color))
            return
        }

        var path = Path()
        path.move(to: CGPoint(x: first.x * size.width, y: first.y * size.height))
        for point in points.dropFirst() {
            path.addLine(to: CGPoint(x: point.x * size.width, y: point.y * size.height))
        }
        if style == .neon {
            var glowContext = context
            glowContext.opacity = 0.35
            glowContext.stroke(
                path,
                with: .color(color),
                style: StrokeStyle(lineWidth: lineWidth * 3, lineCap: .round, lineJoin: .round),
            )
        }
        var styledContext = context
        styledContext.opacity = style.opacity
        styledContext.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round),
        )
    }
}
