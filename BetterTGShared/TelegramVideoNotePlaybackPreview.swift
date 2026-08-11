// TelegramVideoNotePlaybackPreview.swift

import AVKit
import SwiftUI

struct TelegramVideoNotePlaybackPreview: View {
    // MARK: Internal

    let sourceURLs: [URL]
    let trimRange: Range<Double>
    let isMuted: Bool

    var body: some View {
        VideoPlayer(player: player)
            .task(id: PlaybackConfiguration(sourceURLs: sourceURLs, trimRange: trimRange)) {
                do {
                    let asset = try await TelegramVideoNoteEditing.trimmedAsset(
                        sourceURLs: sourceURLs,
                        trimRange: trimRange,
                    )
                    guard !Task.isCancelled else { return }
                    looper = nil
                    player.removeAllItems()
                    looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(asset: asset))
                    player.isMuted = isMuted
                    player.play()
                } catch {
                    looper = nil
                    player.removeAllItems()
                }
            }
            .onChange(of: isMuted) {
                player.isMuted = isMuted
            }
            .onDisappear {
                player.pause()
                looper = nil
                player.removeAllItems()
            }
    }

    // MARK: Private

    private struct PlaybackConfiguration: Hashable {
        let sourceURLs: [URL]
        let trimRange: Range<Double>
    }

    @State private var player = AVQueuePlayer()
    @State private var looper: AVPlayerLooper?
}
