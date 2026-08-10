// TelegramEditorInspector.swift

import SwiftUI

struct TelegramEditorInspector: View {
    // MARK: Internal

    @Bindable var editorState: TelegramMediaEditorState

    var body: some View {
        if editorState.tool == .draw {
            VStack(alignment: .leading) {
                ColorPicker("Brush color", selection: $editorState.brushColor, supportsOpacity: true)
                LabeledContent("Brush size") {
                    Slider(value: $editorState.brushWidth, in: 0.003...0.05)
                        .frame(minWidth: 140)
                }
            }
        } else if editorState.selectedOverlay != nil {
            VStack(alignment: .leading) {
                LabeledContent("Scale") {
                    Slider(
                        value: $editorState.selectedScale,
                        in: 0.25...4,
                        onEditingChanged: scaleEditingChanged,
                    )
                    .frame(minWidth: 140)
                }
                LabeledContent("Rotation") {
                    Slider(
                        value: $editorState.selectedRotationDegrees,
                        in: -180...180,
                        onEditingChanged: rotationEditingChanged,
                    )
                    .frame(minWidth: 140)
                }
                HStack {
                    Button("Duplicate", systemImage: "plus.square.on.square", action: editorState.duplicateSelected)
                    Button(
                        "Bring Forward",
                        systemImage: "square.2.layers.3d.top.filled",
                        action: editorState.bringSelectedForward,
                    )
                    Button("Delete", systemImage: "trash", role: .destructive, action: editorState.deleteSelected)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: Private

    private func scaleEditingChanged(_ isEditing: Bool) {
        if isEditing {
            editorState.beginInteraction()
        } else {
            editorState.endInteraction()
        }
    }

    private func rotationEditingChanged(_ isEditing: Bool) {
        if isEditing {
            editorState.beginInteraction()
        } else {
            editorState.endInteraction()
        }
    }
}
