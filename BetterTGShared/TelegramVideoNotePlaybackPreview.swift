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
            .task(id: sourceURLs) {
                do {
                    let asset = try await TelegramVideoNoteEditing.combinedAsset(sourceURLs: sourceURLs)
                    guard !Task.isCancelled else { return }
                    player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
                    configurePlayback()
                } catch {
                    player.replaceCurrentItem(with: nil)
                }
            }
            .onChange(of: trimRange) {
                configurePlayback()
            }
            .onChange(of: isMuted) {
                player.isMuted = isMuted
            }
            .onDisappear {
                player.pause()
                player.replaceCurrentItem(with: nil)
            }
    }

    // MARK: Private

    @State private var player = AVPlayer()

    private func configurePlayback() {
        guard let item = player.currentItem else { return }
        player.isMuted = isMuted
        item.forwardPlaybackEndTime = CMTime(seconds: trimRange.upperBound, preferredTimescale: 600)
        player.seek(
            to: CMTime(seconds: trimRange.lowerBound, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero,
        )
    }
}
