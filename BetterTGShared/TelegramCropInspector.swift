// TelegramCropInspector.swift

import SwiftUI

struct TelegramCropInspector: View {
    // MARK: Internal

    @Bindable var editorState: TelegramMediaEditorState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Aspect Ratio", selection: aspectRatio) {
                ForEach(TelegramMediaCropAspectRatio.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)

            LabeledContent("Zoom") {
                Slider(value: $editorState.cropZoom, in: 1...4, onEditingChanged: cropEditingChanged)
                    .frame(minWidth: 140)
            }
            LabeledContent("Horizontal position") {
                Slider(value: $editorState.cropHorizontalOffset, in: -1...1, onEditingChanged: cropEditingChanged)
                    .frame(minWidth: 140)
            }
            LabeledContent("Vertical position") {
                Slider(value: $editorState.cropVerticalOffset, in: -1...1, onEditingChanged: cropEditingChanged)
                    .frame(minWidth: 140)
            }
            LabeledContent("Rotation") {
                Text(editorState.cropRotationDegrees, format: .number.precision(.fractionLength(0)))
                    .monospacedDigit()
            }
            Slider(
                value: $editorState.cropRotationDegrees,
                in: -45...45,
                step: 1,
                onEditingChanged: cropEditingChanged,
            )
            .accessibilityLabel("Rotation")
            .accessibilityValue("\(Int(editorState.cropRotationDegrees.rounded())) degrees")

            HStack {
                Button("Rotate Left", systemImage: "rotate.left", action: editorState.rotateCropCounterclockwise)
                Button(
                    editorState.crop.isMirrored ? "Remove Mirror" : "Mirror",
                    systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right",
                    action: editorState.toggleCropMirroring,
                )
                Button("Reset Crop", systemImage: "arrow.counterclockwise", action: editorState.resetCrop)
                    .disabled(editorState.crop.isIdentity)
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: Private

    private var aspectRatio: Binding<TelegramMediaCropAspectRatio> {
        Binding(
            get: { editorState.crop.aspectRatio },
            set: { editorState.setCropAspectRatio($0) },
        )
    }

    private func cropEditingChanged(_ isEditing: Bool) {
        if isEditing {
            editorState.beginInteraction()
        } else {
            editorState.endInteraction()
        }
    }
}
