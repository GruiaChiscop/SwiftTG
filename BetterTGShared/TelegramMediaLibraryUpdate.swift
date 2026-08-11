// TelegramMediaLibraryUpdate.swift

import TDLibKit

enum TelegramMediaLibraryUpdate: Equatable, Sendable {
    case favoriteStickers
    case installedStickerSets
    case recentStickers
    case savedAnimations
    case trendingStickerSets

    // MARK: Lifecycle

    init?(_ update: Update) {
        switch update {
        case .updateFavoriteStickers:
            self = .favoriteStickers
        case .updateInstalledStickerSets(let value):
            guard case .stickerTypeRegular = value.stickerType else { return nil }
            self = .installedStickerSets
        case .updateRecentStickers(let value):
            guard !value.isAttached else { return nil }
            self = .recentStickers
        case .updateSavedAnimations:
            self = .savedAnimations
        case .updateTrendingStickerSets(let value):
            guard case .stickerTypeRegular = value.stickerType else { return nil }
            self = .trendingStickerSets
        default:
            return nil
        }
    }

    // MARK: Internal

    var affectsGIFs: Bool {
        self == .savedAnimations
    }

    var affectsStickers: Bool {
        !affectsGIFs
    }
}
