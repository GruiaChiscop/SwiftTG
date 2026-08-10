// TelegramEditorCutoutComposer.swift

import PhotosUI
import SwiftUI

struct TelegramEditorCutoutComposer: View {
    // MARK: Internal

    let onSelected: (TelegramStickerOverlay) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let document {
                    TelegramCutoutEditorScreen(
                        document: document,
                        chooseDifferentPhoto: chooseDifferentPhoto,
                        editorState: editorState,
                    )
                    .disabled(isFinishing)
                } else {
                    TelegramCutoutPhotoPrompt(isProcessing: isProcessing, photoItem: $photoItem)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .accessibilityFocused($errorIsFocused)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Add Cutout")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                        .disabled(isProcessing || isFinishing)
                }
                if document != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        if isFinishing {
                            ProgressView()
                        } else {
                            Button("Add Cutout", action: finish)
                        }
                    }
                }
            }
        }
        .task(id: photoItem) { await processPhoto() }
        .interactiveDismissDisabled(isProcessing || isFinishing)
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 620)
        #endif
    }

    // MARK: Private

    @AccessibilityFocusState private var errorIsFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var editorState = TelegramCutoutEditorState()
    @State private var photoItem: PhotosPickerItem?
    @State private var document: TelegramCutoutDocument?
    @State private var isProcessing = false
    @State private var isFinishing = false
    @State private var errorMessage: String?

    @MainActor private func processPhoto() async {
        guard let photoItem else { return }
        isProcessing = true
        defer { isProcessing = false }
        errorMessage = nil
        errorIsFocused = false
        do {
            guard let data = try await photoItem.loadTransferable(type: Data.self) else {
                throw TelegramGifEditorError.invalidCutoutImage
            }
            let document = try await TelegramEditorCutoutProcessing.document(from: data)
            try Task.checkCancellation()
            editorState.prepareForNewPhoto()
            self.document = document
        } catch is CancellationError {
            return
        } catch {
            self.photoItem = nil
            await show(error)
        }
    }

    private func finish() {
        Task { await finishCutout() }
    }

    @MainActor private func finishCutout() async {
        guard let document, !isFinishing else { return }
        isFinishing = true
        defer { isFinishing = false }
        errorMessage = nil
        errorIsFocused = false
        var createdOverlay: TelegramStickerOverlay?
        do {
            let overlay = try await TelegramEditorCutoutProcessing.temporaryOverlay(
                from: document,
                strokes: editorState.strokes,
            )
            createdOverlay = overlay
            try Task.checkCancellation()
            onSelected(overlay)
            dismiss()
        } catch is CancellationError {
            if let createdOverlay {
                try? FileManager.default.removeItem(at: createdOverlay.url)
            }
        } catch {
            if let createdOverlay {
                try? FileManager.default.removeItem(at: createdOverlay.url)
            }
            await show(error)
        }
    }

    private func chooseDifferentPhoto() {
        document = nil
        photoItem = nil
        errorMessage = nil
        editorState.prepareForNewPhoto()
    }

    @MainActor private func show(_ error: any Swift.Error) async {
        errorMessage = telegramErrorDescription(error)
        await Task.yield()
        errorIsFocused = true
    }
}
