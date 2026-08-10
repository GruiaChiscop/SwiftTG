// TelegramStickerRasterPreview.swift

import ImageIO
import SwiftUI
import TDLibKit

struct TelegramStickerRasterPreview: View {
    // MARK: Internal

    let sticker: Sticker
    let service: any TelegramService

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView()
            }
        }
        .task(id: sticker.sticker.id) { await load() }
    }

    // MARK: Private

    @State private var image: CGImage?

    @MainActor private func load() async {
        guard image == nil else { return }
        guard let file = try? await service.downloadFile(
            fileId: sticker.sticker.id,
            limit: 0,
            offset: 0,
            priority: 16,
            synchronous: true,
        ), file.local.isDownloadingCompleted, !file.local.path.isEmpty else { return }
        let url = URL(filePath: file.local.path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return }
        image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
