// TelegramEditorCutoutComposer.swift

import PhotosUI
import SwiftUI

struct TelegramEditorCutoutComposer: View {
    // MARK: Internal

    let onSelected: (TelegramStickerOverlay) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "person.crop.rectangle")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                Text("Choose a photo and BetterTG will isolate its main subject automatically.")
                    .multilineTextAlignment(.center)

                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Choose Photo", systemImage: "photo.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isProcessing)

                if isProcessing {
                    ProgressView("Cutting out subject…")
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
                }
            }
        }
        .task(id: photoItem) { await processPhoto() }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 360)
        #endif
    }

    // MARK: Private

    @AccessibilityFocusState private var errorIsFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var photoItem: PhotosPickerItem?
    @State private var isProcessing = false
    @State private var errorMessage: String?

    @MainActor private func processPhoto() async {
        guard let photoItem else { return }
        isProcessing = true
        defer { isProcessing = false }
        errorMessage = nil
        errorIsFocused = false
        var createdOverlay: TelegramStickerOverlay?
        do {
            guard let data = try await photoItem.loadTransferable(type: Data.self) else {
                throw TelegramGifEditorError.invalidCutoutImage
            }
            let overlay = try await TelegramEditorCutoutProcessing.overlay(from: data)
            createdOverlay = overlay
            try Task.checkCancellation()
            onSelected(overlay)
            dismiss()
        } catch is CancellationError {
            if let createdOverlay {
                try? FileManager.default.removeItem(at: createdOverlay.url)
            }
            return
        } catch {
            if let createdOverlay {
                try? FileManager.default.removeItem(at: createdOverlay.url)
            }
            errorMessage = telegramErrorDescription(error)
            self.photoItem = nil
            await Task.yield()
            errorIsFocused = true
        }
    }
}
