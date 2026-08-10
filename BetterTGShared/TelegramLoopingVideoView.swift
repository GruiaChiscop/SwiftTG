// TelegramLoopingVideoView.swift

import AVKit
import SwiftUI

struct TelegramLoopingVideoView: View {
    // MARK: Internal

    let fileURL: URL
    let shouldPlay: Bool

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
                    .disabled(true)
            } else {
                ProgressView()
            }
        }
        .task(id: fileURL) { configurePlayer() }
        .onChange(of: shouldPlay) { _, _ in updatePlayback() }
        .onDisappear { player?.pause() }
        .accessibilityHidden(true)
    }

    // MARK: Private

    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?

    @MainActor private func configurePlayer() {
        let queuePlayer = AVQueuePlayer()
        queuePlayer.isMuted = true
        looper = AVPlayerLooper(player: queuePlayer, templateItem: AVPlayerItem(url: fileURL))
        player = queuePlayer
        updatePlayback(player: queuePlayer)
    }

    @MainActor private func updatePlayback(player explicitPlayer: AVQueuePlayer? = nil) {
        guard let player = explicitPlayer ?? player else { return }
        if shouldPlay {
            player.play()
        } else {
            player.pause()
        }
    }
}
