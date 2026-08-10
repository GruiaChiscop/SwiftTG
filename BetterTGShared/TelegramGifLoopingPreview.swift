// TelegramGifLoopingPreview.swift

import AVKit
import SwiftUI
import TDLibKit

// MARK: - TelegramGifLoopingPreview

struct TelegramGifLoopingPreview: View {
    // MARK: Internal

    let animation: TDLibKit.Animation
    let service: any TelegramService

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
                    .disabled(true)
            } else {
                ProgressView("Loading GIF")
            }
        }
        .task(id: animation.animation.id) { await load() }
        .onDisappear { player?.pause() }
        .accessibilityLabel("GIF preview")
    }

    // MARK: Private

    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?

    @MainActor private func load() async {
        guard player == nil else { return }
        guard let file = try? await service.downloadFile(
            fileId: animation.animation.id,
            limit: 0,
            offset: 0,
            priority: 16,
            synchronous: true,
        ), file.local.isDownloadingCompleted, !file.local.path.isEmpty else { return }

        let item = AVPlayerItem(url: URL(filePath: file.local.path))
        let queuePlayer = AVQueuePlayer()
        queuePlayer.isMuted = true
        looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
        player = queuePlayer
        queuePlayer.play()
    }
}
