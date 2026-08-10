// TelegramEditorStickerGrid.swift

import SwiftUI
import TDLibKit

struct TelegramEditorStickerGrid: View {
    let stickers: [Sticker]
    let packTitles: [TdInt64: String]
    let service: any TelegramService
    let selectingFileId: Int?
    let onSelect: (Sticker) -> Void

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 76, maximum: 96), spacing: 12)],
            spacing: 12,
        ) {
            ForEach(stickers, id: \.sticker.id) { sticker in
                let presentation = TelegramStickerPresentation(sticker)
                Button(action: { onSelect(sticker) }) {
                    ZStack(alignment: .topTrailing) {
                        TelegramEditorStickerPreview(sticker: sticker, service: service)
                            .accessibilityHidden(true)
                        if presentation.isPremium {
                            Image(systemName: "star.fill")
                                .foregroundStyle(.white)
                                .padding(5)
                                .background(.tint, in: Circle())
                                .accessibilityHidden(true)
                        }
                        if selectingFileId == sticker.sticker.id {
                            ProgressView()
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(minHeight: 76)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(selectingFileId != nil)
                .accessibilityLabel(presentation.pickerAccessibilityLabel(packTitle: packTitles[sticker.setId]))
            }
        }
        .padding(.vertical, 4)
    }
}
