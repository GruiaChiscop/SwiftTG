// TelegramCutoutEditorScreen.swift

import SwiftUI

struct TelegramCutoutEditorScreen: View {
    let document: TelegramCutoutDocument
    let chooseDifferentPhoto: () -> Void

    @Bindable var editorState: TelegramCutoutEditorState

    var body: some View {
        VStack(spacing: 16) {
            Text("Refine the automatic mask with Erase or Restore, then add the cutout.")
                .multilineTextAlignment(.center)

            TelegramCutoutCanvas(document: document, editorState: editorState)
                .aspectRatio(
                    Double(document.sourceImage.width) / Double(document.sourceImage.height),
                    contentMode: .fit,
                )
                .frame(maxHeight: 420)

            TelegramCutoutEditorControls(
                chooseDifferentPhoto: chooseDifferentPhoto,
                editorState: editorState,
            )
        }
    }
}
