// TelegramStickerOverlayFormat.swift

enum TelegramStickerOverlayFormat: Equatable, Sendable {
    case staticImage
    case tgs
    case webm

    // MARK: Internal

    var isAnimated: Bool {
        self != .staticImage
    }
}
