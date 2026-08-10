// TelegramCutoutEditorControls.swift

import SwiftUI

struct TelegramCutoutEditorControls: View {
    // MARK: Internal

    let chooseDifferentPhoto: () -> Void

    @Bindable var editorState: TelegramCutoutEditorState

    var body: some View {
        VStack(alignment: .leading) {
            Picker("Mask tool", selection: $editorState.mode) {
                ForEach(TelegramCutoutMaskMode.allCases) { mode in
                    Text(mode.title)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)

            LabeledContent("Brush size") {
                Slider(value: $editorState.brushWidth, in: 0.02...0.25)
                    .frame(minWidth: 140)
            }

            Text("Mask edits: \(editorState.strokes.count)")
                .foregroundStyle(.secondary)

            ViewThatFits(in: .horizontal) {
                HStack {
                    actionButtons
                }
                VStack(alignment: .leading) {
                    actionButtons
                }
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: Private

    @ViewBuilder private var actionButtons: some View {
        Button("Undo Mask Edit", systemImage: "arrow.uturn.backward", action: editorState.undo)
            .disabled(!editorState.canUndo)
        Button("Redo Mask Edit", systemImage: "arrow.uturn.forward", action: editorState.redo)
            .disabled(!editorState.canRedo)
        Button("Reset Mask Edits", systemImage: "arrow.counterclockwise", action: editorState.resetEdits)
            .disabled(!editorState.canReset)
        Button("Choose Different Photo", systemImage: "photo", action: chooseDifferentPhoto)
    }
}
