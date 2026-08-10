// TelegramScheduledSticker.swift

import TDLibKit

// MARK: - TelegramScheduledSticker

struct TelegramScheduledSticker: Identifiable {
    let sticker: Sticker

    var id: Int { sticker.sticker.id }
}
