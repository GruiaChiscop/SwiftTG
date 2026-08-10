// TelegramStickersAndGifsPicker.swift

import SwiftUI
import TDLibKit

// MARK: - TelegramStickersAndGifsPickerView

/// One composer control with a segmented switcher over the same search field, rather than two
/// separate buttons each opening their own picker.
/// `TelegramStickerPickerContent`/`TelegramGifPickerContent` are the exact same content either
/// picker uses standalone; only the shared chrome lives here. The picker deliberately owns no
/// navigation stack or toolbar because it can be embedded directly inside an existing conversation
/// navigation destination. Presentation is owned by the composer so the picker can be inline on
/// iOS and a popover on macOS without obscuring the conversation.
struct TelegramStickersAndGifsPickerView<StickerPreview: View, GifPreview: View>: View {
    // MARK: Lifecycle

    init(
        service: any TelegramService,
        chatId: Int64,
        replyToMessageId: Int64?,
        topicId: MessageTopic? = nil,
        onSent: @escaping @MainActor () async -> Void,
        onClose: @escaping () -> Void,
        @ViewBuilder stickerPreview: @escaping (Sticker) -> StickerPreview,
        @ViewBuilder gifPreview: @escaping (TDLibKit.Animation) -> GifPreview,
    ) {
        self.service = service
        self.chatId = chatId
        self.replyToMessageId = replyToMessageId
        self.topicId = topicId
        self.onSent = onSent
        self.onClose = onClose
        self.stickerPreview = stickerPreview
        self.gifPreview = gifPreview
    }

    // MARK: Internal

    enum Tab: String, CaseIterable {
        case stickers = "Stickers"
        case gifs = "GIFs"
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Picker("Content Type", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 200)

                HStack {
                    Spacer()
                    Button("Close", action: onClose)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            TextField(tab == .stickers ? "Search stickers" : "Search GIFs", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .padding(.bottom, 8)

            Divider()

            Group {
                switch tab {
                case .stickers:
                    TelegramStickerPickerContent(
                        service: service,
                        chatId: chatId,
                        replyToMessageId: replyToMessageId,
                        topicId: topicId,
                        query: query,
                        onSent: didSend,
                        preview: stickerPreview,
                    )
                case .gifs:
                    TelegramGifPickerContent(
                        service: service,
                        chatId: chatId,
                        replyToMessageId: replyToMessageId,
                        topicId: topicId,
                        query: query,
                        onSent: didSend,
                        preview: gifPreview,
                    )
                }
            }
        }
    }

    // MARK: Private

    @State private var query = ""
    @State private var tab = Tab.stickers

    private let service: any TelegramService
    private let chatId: Int64
    private let replyToMessageId: Int64?
    private let topicId: MessageTopic?
    private let onSent: @MainActor () async -> Void
    private let onClose: () -> Void
    private let stickerPreview: (Sticker) -> StickerPreview
    private let gifPreview: (TDLibKit.Animation) -> GifPreview

    @MainActor private func didSend() async {
        await onSent()
        onClose()
    }
}
