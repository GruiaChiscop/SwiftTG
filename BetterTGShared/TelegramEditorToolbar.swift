// TelegramEditorToolbar.swift

import SwiftUI

struct TelegramEditorToolbar: View {
    @Bindable var editorState: TelegramMediaEditorState

    let addText: () -> Void
    let addEmoji: () -> Void
    let addSticker: () -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack {
                Button("Select", systemImage: editorState.tool == .select ? "cursorarrow.rays" : "cursorarrow") {
                    editorState.tool = .select
                }
                .tint(editorState.tool == .select ? .accentColor : .secondary)

                Button("Draw", systemImage: editorState.tool == .draw ? "pencil.tip.crop.circle.fill" : "pencil.tip") {
                    editorState.tool = .draw
                    editorState.select(nil)
                }
                .tint(editorState.tool == .draw ? .accentColor : .secondary)

                Button("Text", systemImage: "textformat", action: addText)
                Button("Emoji", systemImage: "face.smiling", action: addEmoji)
                Button("Sticker", systemImage: "photo.on.rectangle.angled", action: addSticker)

                Divider()
                    .frame(height: 24)

                Button("Undo", systemImage: "arrow.uturn.backward", action: editorState.undo)
                    .disabled(!editorState.canUndo)
                Button("Redo", systemImage: "arrow.uturn.forward", action: editorState.redo)
                    .disabled(!editorState.canRedo)
            }
            .buttonStyle(.bordered)
        }
        .scrollIndicators(.hidden)
    }
}
