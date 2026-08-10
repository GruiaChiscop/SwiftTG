// TelegramCropGestureOverlay.swift

import SwiftUI

struct TelegramCropGestureOverlay: View {
    // MARK: Internal

    @Bindable var editorState: TelegramMediaEditorState

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .contentShape(.rect)
                .gesture(dragGesture(in: proxy.size))
                .simultaneousGesture(magnificationGesture)
                .simultaneousGesture(rotationGesture)
        }
        .accessibilityHidden(true)
    }

    // MARK: Private

    @State private var dragStartOffsets: CGSize?
    @State private var magnificationStartZoom: Double?
    @State private var rotationStartDegrees: Double?
    @State private var isDragging = false
    @State private var isMagnifying = false
    @State private var isRotating = false

    private var rotationGesture: some Gesture {
        RotateGesture()
            .onChanged { value in
                if !isRotating {
                    isRotating = true
                    rotationStartDegrees = editorState.cropRotationDegrees
                    editorState.beginInteraction()
                }
                editorState.cropRotationDegrees =
                    (rotationStartDegrees ?? editorState.cropRotationDegrees) + value.rotation.degrees
            }
            .onEnded { _ in
                rotationStartDegrees = nil
                isRotating = false
                endInteractionIfNeeded()
            }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                if !isMagnifying {
                    isMagnifying = true
                    magnificationStartZoom = editorState.cropZoom
                    editorState.beginInteraction()
                }
                editorState.cropZoom = (magnificationStartZoom ?? editorState.cropZoom) * value
            }
            .onEnded { _ in
                magnificationStartZoom = nil
                isMagnifying = false
                endInteractionIfNeeded()
            }
    }

    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    dragStartOffsets = CGSize(
                        width: editorState.cropHorizontalOffset,
                        height: editorState.cropVerticalOffset,
                    )
                    editorState.beginInteraction()
                }
                guard let dragStartOffsets, size.width > 0, size.height > 0 else { return }
                editorState.cropHorizontalOffset = dragStartOffsets.width - value.translation.width / (size.width / 2)
                editorState.cropVerticalOffset = dragStartOffsets.height - value.translation.height / (size.height / 2)
            }
            .onEnded { _ in
                dragStartOffsets = nil
                isDragging = false
                endInteractionIfNeeded()
            }
    }

    private func endInteractionIfNeeded() {
        if !isDragging, !isMagnifying, !isRotating {
            editorState.endInteraction()
        }
    }
}
