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

            if let sendPermission {
                if let restrictionMessage = sendPermission.message(for: selectedTab) {
                    ContentUnavailableView(
                        "Sending Restricted",
                        systemImage: "nosign",
                        description: Text(restrictionMessage),
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    pickerContent
                }
            } else {
                ProgressView("Checking permissions")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: "\(chatId):\(permissionRevision)") { await loadSendPermission() }
        .onReceive(service.updatePublisher) { update in
            guard TelegramMediaSendPermission.shouldReload(after: update, chatID: chatId) else { return }
            permissionRevision &+= 1
        }
    }

    // MARK: Private

    @AppStorage(TelegramMediaPickerTab.defaultsKey) private var selectedTabRawValue = TelegramMediaPickerTab.stickers
        .rawValue
    @State private var permissionRevision: UInt = 0
    @State private var query = ""
    @State private var sendPermission: TelegramMediaSendPermission?

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

    @ViewBuilder private var pickerContent: some View {
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

    @MainActor private func loadSendPermission() async {
        do {
            let permission = try await TelegramMediaSendPermission.resolve(service: service, chatID: chatId)
            guard !Task.isCancelled else { return }
            sendPermission = permission
        } catch is CancellationError {
            return
        } catch {
            // Permission loading is advisory. If it fails, let TDLib make the authoritative send
            // decision and surface its existing user-facing error rather than blocking the picker.
            sendPermission = .allowed
        }
    }

    @MainActor private func didSend() async {
        await onSent()
        onClose()
    }
}
