// TelegramStickersAndGifsPicker.swift

import SwiftUI
import TDLibKit

// MARK: - TelegramStickersAndGifsPickerView

/// One button, one sheet, matching how real Telegram's own composer works - a segmented switcher
/// over the same search field, rather than two separate buttons each opening their own picker.
/// `TelegramStickerPickerContent`/`TelegramGifPickerContent` are the exact same content either
/// picker uses standalone; only the shared chrome (`NavigationStack`, search field, tab switcher)
/// lives here.
struct TelegramStickersAndGifsPickerView<StickerPreview: View, GifPreview: View>: View {
    // MARK: Lifecycle

    init(
        service: any TelegramService,
        chatId: Int64,
        replyToMessageId: Int64?,
        topicId: MessageTopic? = nil,
        onSent: @escaping @MainActor () async -> Void,
        @ViewBuilder stickerPreview: @escaping (Sticker) -> StickerPreview,
        @ViewBuilder gifPreview: @escaping (TDLibKit.Animation) -> GifPreview,
    ) {
        self.service = service
        self.chatId = chatId
        self.replyToMessageId = replyToMessageId
        self.topicId = topicId
        self.onSent = onSent
        self.stickerPreview = stickerPreview
        self.gifPreview = gifPreview
    }

    // MARK: Internal

    enum Tab: String, CaseIterable {
        case stickers = "Stickers"
        case gifs = "GIFs"
    }

    var body: some View {
        NavigationStack {
            Group {
                switch tab {
                case .stickers:
                    TelegramStickerPickerContent(
                        service: service,
                        chatId: chatId,
                        replyToMessageId: replyToMessageId,
                        topicId: topicId,
                        query: query,
                        onSent: onSent,
                        preview: stickerPreview,
                    )
                case .gifs:
                    TelegramGifPickerContent(
                        service: service,
                        chatId: chatId,
                        replyToMessageId: replyToMessageId,
                        topicId: topicId,
                        query: query,
                        onSent: onSent,
                        preview: gifPreview,
                    )
                }
            }
            .navigationTitle(tab.rawValue)
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .searchable(text: $query, prompt: tab == .stickers ? "Search stickers" : "Search GIFs")
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Picker("Content Type", selection: $tab) {
                            ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 200)
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var tab = Tab.stickers

    private let service: any TelegramService
    private let chatId: Int64
    private let replyToMessageId: Int64?
    private let topicId: MessageTopic?
    private let onSent: @MainActor () async -> Void
    private let stickerPreview: (Sticker) -> StickerPreview
    private let gifPreview: (TDLibKit.Animation) -> GifPreview
}
