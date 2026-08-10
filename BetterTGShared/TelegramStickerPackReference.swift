// TelegramStickerPackReference.swift

import TDLibKit

struct TelegramStickerPackReference: Equatable, Identifiable, Sendable {
    // MARK: Lifecycle

    init?(sticker: Sticker) {
        guard sticker.setId != 0 else { return nil }
        self.id = sticker.setId
    }

    // MARK: Internal

    let id: TdInt64
}
