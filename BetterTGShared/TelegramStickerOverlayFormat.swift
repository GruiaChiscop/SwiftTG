// TelegramStickerOverlayFormat.swift

enum TelegramStickerOverlayFormat: Equatable, Sendable {
    case staticImage
    case tgs
    case webm
    case video

    // MARK: Internal

    var isAnimated: Bool {
        self != .staticImage
    }
}
