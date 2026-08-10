// TelegramEffectsInspector.swift

import SwiftUI

struct TelegramEffectsInspector: View {
    // MARK: Internal

    @Bindable var editorState: TelegramMediaEditorState

    var body: some View {
        VStack(alignment: .leading) {
            LabeledContent("Brightness") {
                Text(editorState.effects.brightness, format: .number.precision(.fractionLength(2)))
                    .monospacedDigit()
            }
            Slider(
                value: $editorState.effects.brightness,
                in: -1...1,
                onEditingChanged: editingChanged,
            )
            LabeledContent("Contrast") {
                Text(editorState.effects.contrast, format: .number.precision(.fractionLength(2)))
                    .monospacedDigit()
            }
            Slider(
                value: $editorState.effects.contrast,
                in: 0.5...2,
                onEditingChanged: editingChanged,
            )
            LabeledContent("Saturation") {
                Text(editorState.effects.saturation, format: .number.precision(.fractionLength(2)))
                    .monospacedDigit()
            }
            Slider(
                value: $editorState.effects.saturation,
                in: 0...2,
                onEditingChanged: editingChanged,
            )
            LabeledContent("Blur") {
                Text(editorState.effects.blurRadius, format: .number.precision(.fractionLength(1)))
                    .monospacedDigit()
            }
            Slider(
                value: $editorState.effects.blurRadius,
                in: 0...20,
                onEditingChanged: editingChanged,
            )
            Button("Reset Effects", systemImage: "arrow.counterclockwise", action: editorState.resetEffects)
                .buttonStyle(.bordered)
                .disabled(editorState.effects.isIdentity)
        }
    }

    // MARK: Private

    private func editingChanged(_ isEditing: Bool) {
        if isEditing {
            editorState.beginInteraction()
        } else {
            editorState.endInteraction()
        }
    }
}
