// TelegramMediaLibraryUpdateTests.swift

@testable import BetterTG
import TDLibKit
import Testing

struct TelegramMediaLibraryUpdateTests {
    @Test func `ordinary sticker library updates request a sticker refresh`() {
        let updates: [Update] = [
            .updateFavoriteStickers(.init(stickerIds: [1])),
            .updateRecentStickers(.init(isAttached: false, stickerIds: [2])),
            .updateInstalledStickerSets(.init(
                stickerSetIds: [3],
                stickerType: .stickerTypeRegular,
            )),
            .updateTrendingStickerSets(.init(
                stickerSets: .init(isPremium: false, sets: [], totalCount: 0),
                stickerType: .stickerTypeRegular,
            )),
        ]

        for update in updates {
            let mapped = TelegramMediaLibraryUpdate(update)
            #expect(mapped?.affectsStickers == true)
            #expect(mapped?.affectsGIFs == false)
        }
    }

    @Test func `saved animation updates request only a GIF refresh`() {
        let mapped = TelegramMediaLibraryUpdate(.updateSavedAnimations(.init(animationIds: [4])))

        #expect(mapped?.affectsGIFs == true)
        #expect(mapped?.affectsStickers == false)
    }

    @Test func `attached recent stickers and unrelated updates are ignored`() {
        let attached = Update.updateRecentStickers(.init(isAttached: true, stickerIds: [5]))
        let unrelated = Update.updateChatTitle(.init(chatId: 1, title: "Chat"))

        #expect(TelegramMediaLibraryUpdate(attached) == nil)
        #expect(TelegramMediaLibraryUpdate(unrelated) == nil)
    }
}
