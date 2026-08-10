// ChatStickersAndGifsPicker.swift

import SwiftUI

// MARK: - ChatStickersAndGifsPicker

struct ChatStickersAndGifsPicker: View {
    // MARK: Internal

    let onClose: () -> Void

    var body: some View {
        TelegramStickersAndGifsPickerView(
            service: chatVM.service,
            chatId: chatVM.customChat.chat.id,
            replyToMessageId: chatVM.replyMessage?.id,
            topicId: chatVM.messageTopic,
            onSent: {
                chatVM.replyMessage = nil
                await chatVM.updateDraft()
            },
            onClose: onClose,
        ) { sticker in
            TelegramStickerView(
                sticker: sticker,
                service: chatVM.service,
                maxSide: 76,
                playsAnimation: false,
            )
        } gifPreview: { animation in
            if let thumbnail = animation.thumbnail {
                AsyncTdImage(id: thumbnail.file.id) { image, _ in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(.black.opacity(0.15))
                }
            } else {
                Rectangle().fill(.black.opacity(0.15))
            }
        }
    }

    // MARK: Private

    @Environment(ChatVM.self) private var chatVM
}
