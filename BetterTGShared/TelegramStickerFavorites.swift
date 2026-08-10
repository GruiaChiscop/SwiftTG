// TelegramStickerFavorites.swift

import Observation
import TDLibKit

// MARK: - TelegramStickerFavoriteAction

enum TelegramStickerFavoriteAction: Equatable, Sendable {
    case add
    case remove

    // MARK: Lifecycle

    init(isFavorite: Bool) {
        self = isFavorite ? .remove : .add
    }

    // MARK: Internal

    var title: String {
        switch self {
        case .add: "Add to Favorites"
        case .remove: "Remove from Favorites"
        }
    }

    var systemImage: String {
        switch self {
        case .add: "star"
        case .remove: "star.slash"
        }
    }

    func applying(to fileIds: Set<Int>, stickerFileId: Int) -> Set<Int> {
        var updated = fileIds
        switch self {
        case .add: updated.insert(stickerFileId)
        case .remove: updated.remove(stickerFileId)
        }
        return updated
    }
}

// MARK: - TelegramFavoriteStickersStore

@MainActor @Observable final class TelegramFavoriteStickersStore {
    // MARK: Lifecycle

    init(service: any TelegramService) {
        self.service = service
    }

    // MARK: Internal

    private(set) var fileIds = Set<Int>()
    private(set) var mutatingFileIds = Set<Int>()
    private(set) var hasLoaded = false

    func action(for sticker: Sticker) -> TelegramStickerFavoriteAction? {
        guard hasLoaded, sticker.setId != 0,
              case .stickerFullTypeRegular = sticker.fullType
        else { return nil }
        return TelegramStickerFavoriteAction(isFavorite: fileIds.contains(sticker.sticker.id))
    }

    func apply(_ update: UpdateFavoriteStickers) {
        loadGeneration &+= 1
        fileIds = Set(update.stickerIds)
        hasLoaded = true
    }

    func load() async {
        loadGeneration &+= 1
        let generation = loadGeneration
        do {
            let stickers = try await service.getFavoriteStickers()
            guard !Task.isCancelled, generation == loadGeneration else { return }
            fileIds = Set(stickers.stickers.map(\.sticker.id))
            hasLoaded = true
        } catch is CancellationError {
            return
        } catch {
            // Favorites are an additive message action. Keep the last valid snapshot on a
            // transient TDLib failure rather than presenting an incorrect add/remove state.
        }
    }

    func toggle(_ sticker: Sticker) async throws {
        guard let action = action(for: sticker) else { return }
        let fileId = sticker.sticker.id
        guard mutatingFileIds.insert(fileId).inserted else { return }
        defer { mutatingFileIds.remove(fileId) }
        // A load started before this mutation may contain the old favorite state. Invalidate it
        // before awaiting TDLib, then again before applying the confirmed local transition so a
        // refresh that raced the mutation can't overwrite the newer result.
        loadGeneration &+= 1

        let file = InputFile.inputFileId(.init(id: fileId))
        _ =
            switch action {
            case .add:
                try await service.addFavoriteSticker(sticker: file)
            case .remove:
                try await service.removeFavoriteSticker(sticker: file)
            }
        loadGeneration &+= 1
        fileIds = action.applying(to: fileIds, stickerFileId: fileId)
    }

    // MARK: Private

    @ObservationIgnored private let service: any TelegramService
    @ObservationIgnored private var loadGeneration: UInt64 = 0
}
