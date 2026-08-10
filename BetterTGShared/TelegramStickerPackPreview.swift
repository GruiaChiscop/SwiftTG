// TelegramStickerPackPreview.swift

import SwiftUI
import TDLibKit

struct TelegramStickerPackPreview<Preview: View>: View {
    // MARK: Internal

    let reference: TelegramStickerPackReference
    let service: any TelegramService
    let onSelect: (Sticker) -> Void
    let preview: (Sticker) -> Preview

    var body: some View {
        NavigationStack {
            Group {
                if let stickerSet {
                    ScrollView {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 76, maximum: 96), spacing: 12)],
                            spacing: 12,
                        ) {
                            ForEach(stickerSet.stickers, id: \.sticker.id) { sticker in
                                stickerButton(sticker, packTitle: stickerSet.title)
                            }
                        }
                        .padding()
                    }
                } else if let errorMessage {
                    ContentUnavailableView(
                        "Sticker Pack Unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage),
                    )
                    .accessibilityFocused($errorIsFocused)
                } else {
                    ProgressView("Loading sticker pack")
                }
            }
            .navigationTitle(stickerSet?.title ?? "Sticker Pack")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: dismiss.callAsFunction)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 480)
        #endif
        .task(id: reference.id) { await loadStickerSet() }
    }

    // MARK: Private

    @AccessibilityFocusState private var errorIsFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var stickerSet: StickerSet?
    @State private var errorMessage: String?

    private func stickerButton(_ sticker: Sticker, packTitle: String) -> some View {
        let presentation = TelegramStickerPresentation(sticker)
        return Button {
            onSelect(sticker)
            dismiss()
        } label: {
            preview(sticker)
                .accessibilityHidden(true)
                .frame(minHeight: 76)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(presentation.pickerAccessibilityLabel(packTitle: packTitle))
    }

    @MainActor private func loadStickerSet() async {
        stickerSet = nil
        errorMessage = nil
        do {
            let loadedStickerSet = try await service.getStickerSet(setId: reference.id)
            guard !Task.isCancelled else { return }
            stickerSet = loadedStickerSet
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = telegramErrorDescription(error)
            await Task.yield()
            errorIsFocused = true
        }
    }
}
