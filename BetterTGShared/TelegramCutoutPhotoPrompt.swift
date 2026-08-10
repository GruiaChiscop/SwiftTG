// TelegramCutoutPhotoPrompt.swift

import PhotosUI
import SwiftUI

struct TelegramCutoutPhotoPrompt: View {
    let isProcessing: Bool

    @Binding var photoItem: PhotosPickerItem?

    var body: some View {
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
