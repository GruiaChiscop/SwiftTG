// TelegramCutoutCanvas.swift

import SwiftUI

struct TelegramCutoutCanvas: View {
    // MARK: Internal

    let document: TelegramCutoutDocument

    @Bindable var editorState: TelegramCutoutEditorState

    var body: some View {
        GeometryReader { proxy in
            Image(decorative: document.sourceImage, scale: 1)
                .resizable()
                .scaledToFit()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .mask {
                    TelegramCutoutMaskArtwork(
                        initialMask: document.initialMask,
                        strokes: editorState.strokes,
                        activeStroke: activeStroke,
                    )
                }
                .contentShape(.rect)
                .gesture(drawingGesture(in: proxy.size))
        }
        .background(.secondary.opacity(0.15))
        .clipShape(.rect(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cutout mask editing canvas")
        .accessibilityValue("\(editorState.mode.title), \(editorState.strokes.count) edits")
        .accessibilityHint("Drag over the image to erase or restore parts of the subject")
    }

    // MARK: Private

    @State private var activePoints = [TelegramEditorPoint]()

    private var activeStroke: TelegramCutoutMaskStroke? {
        guard !activePoints.isEmpty else { return nil }
        return .init(
            points: activePoints,
            width: editorState.brushWidth,
            mode: editorState.mode,
        )
    }

    private func drawingGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard size.width > 0, size.height > 0 else { return }
                let point = TelegramEditorPoint(
                    x: min(max(value.location.x / size.width, 0), 1),
                    y: min(max(value.location.y / size.height, 0), 1),
                )
                guard shouldAppend(point) else { return }
                activePoints.append(point)
            }
            .onEnded { _ in
                editorState.addStroke(points: activePoints)
                activePoints.removeAll(keepingCapacity: true)
            }
    }

    private func shouldAppend(_ point: TelegramEditorPoint) -> Bool {
        guard let last = activePoints.last else { return true }
        let deltaX = point.x - last.x
        let deltaY = point.y - last.y
        return deltaX * deltaX + deltaY * deltaY >= 0.000_004
    }
}
