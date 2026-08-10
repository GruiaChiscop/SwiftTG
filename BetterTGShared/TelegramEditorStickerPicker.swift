// TelegramEditorStickerPicker.swift

import SwiftUI

struct TelegramEditorStickerPicker: View {
    // MARK: Internal

    let service: any TelegramService
    let chatId: Int64
    let onSelected: (TelegramStickerOverlay) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Overlay Type", selection: $selectedSection) {
                    ForEach(TelegramEditorOverlayPickerSection.allCases) { section in
                        Label(section.title, systemImage: section.systemImage)
                            .tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                switch selectedSection {
                case .stickers:
                    TelegramEditorStickerLibrary(
                        service: service,
                        chatId: chatId,
                        query: query,
                        onSelected: select,
                    )
                case .gifs:
                    TelegramEditorGifLibrary(
                        service: service,
                        chatId: chatId,
                        query: query,
                        onSelected: select,
                    )
                }
            }
            .navigationTitle("Add Overlay")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .searchable(text: $query, prompt: selectedSection.searchPrompt)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", role: .cancel) { dismiss() }
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 560)
        #endif
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var selectedSection = TelegramEditorOverlayPickerSection.stickers
    @State private var query = ""

    private func select(_ overlay: TelegramStickerOverlay) {
        onSelected(overlay)
        dismiss()
    }
}
