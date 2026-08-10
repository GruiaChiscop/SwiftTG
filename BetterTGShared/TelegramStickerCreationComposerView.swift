// TelegramStickerCreationComposerView.swift

import ImageIO
import PhotosUI
import SwiftUI
import TDLibKit

/// Progressive-disclosure flow: pick a photo, crop it (`TelegramStickerCropView`), give the sticker
/// an emoji, then create it. No pack name/title is ever asked - matches Telegram's own Sticker
/// Editor, which silently creates (or reuses) a pack rather than prompting for one; see
/// `TelegramStickerCreation.createOrAddSticker`. Presented from `TelegramStickerPickerContent` on both
/// platforms. Works in `CGImage`/`Data` throughout (never `UIImage`/`NSImage`), which is what keeps
/// this file cross-platform without conditional compilation for the image type.
struct TelegramStickerCreationComposerView: View {
    // MARK: Internal

    let service: any TelegramService
    let onCreated: (StickerSet) async -> Void

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Create Sticker")
                #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                #endif
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel", role: .cancel) { dismiss() }
                        }
                        if croppedPNGData != nil {
                            ToolbarItem(placement: .confirmationAction) {
                                if isCreating {
                                    ProgressView()
                                } else {
                                    Button("Create") { Task { await create() } }
                                        .disabled(!draft.isValid)
                                }
                            }
                        }
                    }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 560)
        #endif
        .onChange(of: pickedPhotoItem) { _, newValue in
            Task { await loadPickedPhoto(newValue) }
        }
        .alert("Couldn't Create Sticker", isPresented: errorIsPresented) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    @State private var pickedPhotoItem: PhotosPickerItem?
    @State private var pickedCGImage: CGImage?
    @State private var croppedPNGData: Data?
    @State private var draft = TelegramStickerCreationDraft()
    @State private var isCreating = false
    @State private var errorMessage: String?

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    errorMessage = nil
                }
            },
        )
    }

    @ViewBuilder private var content: some View {
        if let pickedCGImage, croppedPNGData == nil {
            TelegramStickerCropView(sourceImage: pickedCGImage) { pngData in
                croppedPNGData = pngData
            } onChooseDifferentPhoto: {
                self.pickedCGImage = nil
                pickedPhotoItem = nil
            }
        } else if let croppedPNGData {
            metadataForm(pngData: croppedPNGData)
        } else {
            photoPickerPrompt
        }
    }

    private var photoPickerPrompt: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            PhotosPicker(selection: $pickedPhotoItem, matching: .images) {
                Text("Choose Photo")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func metadataForm(pngData: Data) -> some View {
        Form {
            Section {
                if let previewImage = Self.cgImage(from: pngData) {
                    HStack {
                        Spacer()
                        Image(previewImage, scale: 1, label: Text("Sticker preview"))
                            .resizable()
                            .frame(width: 120, height: 120)
                            .accessibilityHidden(true)
                        Spacer()
                    }
                }
                Button("Choose a Different Photo") {
                    croppedPNGData = nil
                    pickedCGImage = nil
                    pickedPhotoItem = nil
                }
            }

            Section {
                TextField("Emoji", text: $draft.emojis)
                    .onChange(of: draft.emojis) { _, newValue in
                        let filtered = TelegramStickerCreationDraft.filteredToEmoji(newValue)
                        if filtered != newValue {
                            draft.emojis = filtered
                        }
                    }
            } footer: {
                Text("Pick an emoji for this sticker.")
            }

            if isCreating {
                Section {
                    ProgressView("Creating…")
                }
            }
        }
    }

    private static func cgImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    @MainActor private func loadPickedPhoto(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
        pickedCGImage = Self.cgImage(from: data)
    }

    @MainActor private func create() async {
        guard let croppedPNGData else { return }
        isCreating = true
        defer { isCreating = false }
        do {
            let stickerSet = try await TelegramStickerCreation.createOrAddSticker(
                draft: draft,
                pngData: croppedPNGData,
                service: service,
            )
            await onCreated(stickerSet)
            dismiss()
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }
}
