// TelegramStickerOverlayFormat.swift

enum TelegramStickerOverlayFormat: Equatable, Sendable {
    case webp
    case tgs
    case webm

    // MARK: Internal

    var isAnimated: Bool {
        self != .webp
    }
}
