// TelegramEditorOverlaySelection.swift

import Foundation
import TDLibKit

enum TelegramEditorOverlaySelection {
    // MARK: Internal

    static func sticker(fileURL: URL, sticker: Sticker) -> TelegramStickerOverlay {
        TelegramStickerOverlay(
            url: fileURL,
            pixelWidth: sticker.width,
            pixelHeight: sticker.height,
            format: stickerFormat(sticker.format),
        )
    }

    static func gif(fileURL: URL, width: Int, height: Int) -> TelegramStickerOverlay {
        TelegramStickerOverlay(
            url: fileURL,
            pixelWidth: width,
            pixelHeight: height,
            format: .video,
        )
    }

    static func download(
        sticker: Sticker,
        service: any TelegramService,
    ) async throws -> TelegramStickerOverlay {
        let fileURL = try await download(fileId: sticker.sticker.id, service: service)
        return self.sticker(fileURL: fileURL, sticker: sticker)
    }

    static func download(
        animation: TDLibKit.Animation,
        service: any TelegramService,
    ) async throws -> TelegramStickerOverlay {
        let fileURL = try await download(fileId: animation.animation.id, service: service)
        return gif(fileURL: fileURL, width: animation.width, height: animation.height)
    }

    static func stickerFormat(_ format: StickerFormat) -> TelegramStickerOverlayFormat {
        switch format {
        case .stickerFormatWebp: .staticImage
        case .stickerFormatTgs: .tgs
        case .stickerFormatWebm: .webm
        }
    }

    // MARK: Private

    private static func download(
        fileId: Int,
        service: any TelegramService,
    ) async throws -> URL {
        let file = try await service.downloadFile(
            fileId: fileId,
            limit: 0,
            offset: 0,
            priority: 32,
            synchronous: true,
        )
        guard file.local.isDownloadingCompleted, !file.local.path.isEmpty else {
            throw TelegramGifEditorError.downloadFailed
        }
        return URL(filePath: file.local.path)
    }
}
