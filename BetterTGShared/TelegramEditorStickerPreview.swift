// TelegramEditorStickerPreview.swift

import ImageIO
import SwiftUI
import TDLibKit

struct TelegramEditorStickerPreview: View {
    // MARK: Internal

    let sticker: Sticker
    let service: any TelegramService

    var body: some View {
        Group {
            if let fileURL {
                switch sticker.format {
                case .stickerFormatWebp:
                    if let rasterImage {
                        Image(decorative: rasterImage, scale: 1)
                            .resizable()
                            .scaledToFit()
                    } else {
                        ProgressView()
                    }
                case .stickerFormatTgs:
                    TelegramStickerAnimationView(
                        fileURL: fileURL,
                        renderSize: CGSize(width: 88, height: 88),
                        shouldPlay: true,
                    )
                case .stickerFormatWebm:
                    TelegramStickerVideoView(fileURL: fileURL, shouldPlay: true)
                }
            } else {
                ProgressView()
            }
        }
        .task(id: sticker.sticker.id) { await load() }
    }

    // MARK: Private

    @State private var fileURL: URL?
    @State private var rasterImage: CGImage?

    @MainActor private func load() async {
        guard fileURL == nil else { return }
        guard let file = try? await service.downloadFile(
            fileId: sticker.sticker.id,
            limit: 0,
            offset: 0,
            priority: 16,
            synchronous: true,
        ), file.local.isDownloadingCompleted, !file.local.path.isEmpty else { return }
        let url = URL(filePath: file.local.path)
        fileURL = url
        guard case .stickerFormatWebp = sticker.format,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil)
        else { return }
        rasterImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
