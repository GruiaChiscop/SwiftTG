// TelegramDrawingCanvas.swift

import SwiftUI

struct TelegramDrawingCanvas: View {
    // MARK: Internal

    @Bindable var editorState: TelegramMediaEditorState

    var body: some View {
        GeometryReader { proxy in
            TelegramDrawingArtwork(
                strokes: editorState.strokes,
                activePoints: activePoints,
                activeColor: TelegramEditorColor(editorState.brushColor),
                activeWidth: editorState.brushWidth,
                activeStyle: editorState.brushStyle,
            )
            .contentShape(.rect)
            .gesture(drawingGesture(in: proxy.size))
        }
        .allowsHitTesting(editorState.tool == .draw)
        .accessibilityLabel("Drawing canvas")
        .accessibilityHint("Drag to draw on the media")
    }

    // MARK: Private

    @State private var activePoints = [TelegramEditorPoint]()

    private func drawingGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard size.width > 0, size.height > 0 else { return }
                activePoints.append(.init(
                    x: min(max(value.location.x / size.width, 0), 1),
                    y: min(max(value.location.y / size.height, 0), 1),
                ))
            }
            .onEnded { _ in
                editorState.addStroke(points: activePoints)
                activePoints.removeAll(keepingCapacity: true)
            }
    }
}
