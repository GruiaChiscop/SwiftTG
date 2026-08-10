// TelegramStickerPackReference.swift

import TDLibKit

struct TelegramStickerPackReference: Equatable, Identifiable, Sendable {
    // MARK: Lifecycle

    init?(sticker: Sticker) {
        guard sticker.setId != 0 else { return nil }
        self.id = sticker.setId
    }

    init?(messageSticker: MessageSticker) {
        self.init(sticker: messageSticker.sticker)
    }

    // MARK: Internal

    let id: TdInt64
}
