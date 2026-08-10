// TelegramMediaOverlayContent.swift

enum TelegramMediaOverlayContent: Equatable, Sendable {
    case text(String)
    case emoji(String)
    case sticker(TelegramStaticStickerOverlay)
}
