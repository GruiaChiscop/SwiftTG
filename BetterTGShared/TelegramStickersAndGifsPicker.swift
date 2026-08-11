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
struct TelegramStickersAndGifsPickerView<StickerPreview: View, StickerContextPreview: View, GifPreview: View>: View {
    // MARK: Lifecycle

    init(
        service: any TelegramService,
        chatId: Int64,
        replyToMessageId: Int64?,
        allowsSendWhenOnline: Bool,
        topicId: MessageTopic? = nil,
        onSent: @escaping @MainActor () async -> Void,
        onClose: @escaping () -> Void,
        @ViewBuilder stickerPreview: @escaping (Sticker) -> StickerPreview,
        @ViewBuilder stickerContextPreview: @escaping (Sticker) -> StickerContextPreview,
        @ViewBuilder gifPreview: @escaping (TDLibKit.Animation) -> GifPreview,
    ) {
        self.service = service
        self.chatId = chatId
        self.replyToMessageId = replyToMessageId
        self.allowsSendWhenOnline = allowsSendWhenOnline
        self.topicId = topicId
        self.onSent = onSent
        self.onClose = onClose
        self.stickerPreview = stickerPreview
        self.stickerContextPreview = stickerContextPreview
        self.gifPreview = gifPreview
    }

    // MARK: Internal

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Picker("Content Type", selection: $selectedTabRawValue) {
                    ForEach(TelegramMediaPickerTab.allCases) { tab in
                        Text(tab.title).tag(tab.rawValue)
                    }
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

            TextField(selectedTab == .stickers ? "Search stickers" : "Search GIFs", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .padding(.bottom, 8)

            Divider()

            Group {
                switch selectedTab {
                case .stickers:
                    TelegramStickerPickerContent(
                        service: service,
                        chatId: chatId,
                        replyToMessageId: replyToMessageId,
                        allowsSendWhenOnline: allowsSendWhenOnline,
                        topicId: topicId,
                        query: query,
                        onSent: didSend,
                        preview: stickerPreview,
                        contextPreview: stickerContextPreview,
                    )
                case .gifs:
                    TelegramGifPickerContent(
                        service: service,
                        chatId: chatId,
                        replyToMessageId: replyToMessageId,
                        allowsSendWhenOnline: allowsSendWhenOnline,
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

    @AppStorage(TelegramMediaPickerTab.defaultsKey) private var selectedTabRawValue = TelegramMediaPickerTab.stickers
        .rawValue
    @State private var query = ""

    private let service: any TelegramService
    private let chatId: Int64
    private let replyToMessageId: Int64?
    private let allowsSendWhenOnline: Bool
    private let topicId: MessageTopic?
    private let onSent: @MainActor () async -> Void
    private let onClose: () -> Void
    private let stickerPreview: (Sticker) -> StickerPreview
    private let stickerContextPreview: (Sticker) -> StickerContextPreview
    private let gifPreview: (TDLibKit.Animation) -> GifPreview

    private var selectedTab: TelegramMediaPickerTab {
        TelegramMediaPickerTab.selection(storedValue: selectedTabRawValue)
    }

    @MainActor private func didSend() async {
        await onSent()
        onClose()
    }
}
