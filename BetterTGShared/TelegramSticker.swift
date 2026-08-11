// TelegramSticker.swift

import Foundation
import TDLibKit

// MARK: - TelegramStickerKind

enum TelegramStickerKind: Equatable {
    case image
    case vectorAnimation
    case video
}

// MARK: - TelegramStickerPresentation

struct TelegramStickerPresentation: Equatable {
    // MARK: Lifecycle

    init(_ content: MessageSticker) {
        self.init(content.sticker)
    }

    init(_ sticker: Sticker) {
        self.fileId = sticker.sticker.id
        self.thumbnailFileId = sticker.thumbnail?.file.id
        if sticker.width > 0, sticker.height > 0 {
            self.pixelWidth = sticker.width
            self.pixelHeight = sticker.height
        } else {
            self.pixelWidth = 512
            self.pixelHeight = 512
        }
        self.emoji = sticker.emoji
        self.isPremium =
            switch sticker.fullType {
            case .stickerFullTypeRegular(let regular):
                regular.premiumAnimation != nil
            case .stickerFullTypeCustomEmoji, .stickerFullTypeMask:
                false
            }
        self.kind =
            switch sticker.format {
            case .stickerFormatWebp: .image
            case .stickerFormatTgs: .vectorAnimation
            case .stickerFormatWebm: .video
            }
    }

    // MARK: Internal

    let fileId: Int
    let thumbnailFileId: Int?
    let pixelWidth: Int
    let pixelHeight: Int
    let emoji: String
    let isPremium: Bool
    let kind: TelegramStickerKind

    var accessibilityLabel: String {
        emoji.isEmpty ? "Sticker" : "Sticker \(emoji)"
    }

    var isEditable: Bool {
        !isPremium
    }

    func pickerAccessibilityLabel(packTitle: String?) -> String {
        var parts = [isPremium ? "Premium sticker" : "Sticker"]
        if !emoji.isEmpty {
            parts.append(emoji)
        }
        if let packTitle, !packTitle.isEmpty {
            parts.append("from \(packTitle)")
        }
        return parts.joined(separator: ", ")
    }

    func displaySize(maxSide: CGFloat = 224) -> CGSize {
        guard maxSide > 0 else { return .zero }
        let width = CGFloat(pixelWidth)
        let height = CGFloat(pixelHeight)
        let scale = maxSide / max(width, height)
        return CGSize(width: width * scale, height: height * scale)
    }
}
