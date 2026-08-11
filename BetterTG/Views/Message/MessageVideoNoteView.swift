// MessageVideoNoteView.swift

import SwiftUI
import TDLibKit

struct MessageVideoNoteView: View {
    // MARK: Internal

    let message: Message
    let content: MessageVideoNote
    let service: any TelegramService

    @Bindable var player: TelegramVideoNotePlayer

    var body: some View {
        Button(action: togglePlayback) {
            ZStack {
                thumbnail

                if isCurrent, let avPlayer = player.player {
                    TelegramVideoNotePlayerSurface(player: avPlayer)
                }

                playbackControl

                Text(telegramClockDuration(elapsed))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.7), in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(14)
            }
            .frame(width: 220, height: 220)
            .clipShape(Circle())
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        // MessageView exposes the stable, sender-aware accessibility element and activation.
        .accessibilityHidden(true)
    }

    // MARK: Private

    private var elapsed: Int {
        isCurrent ? player.currentTime : 0
    }

    private var isCurrent: Bool {
        player.currentFileId == content.videoNote.video.id
    }

    @ViewBuilder private var thumbnail: some View {
        if let thumbnail = content.videoNote.thumbnail {
            AsyncTdImage(id: thumbnail.file.id, maxPixelSize: 440, service: service) { image, _ in
                image
                    .resizable()
                    .scaledToFill()
                    .blur(radius: content.isSecret && !isCurrent ? 18 : 0)
            } placeholder: {
                Circle().fill(.black.opacity(0.35))
            }
        } else {
            Circle().fill(.black.opacity(0.35))
        }
    }

    @ViewBuilder private var playbackControl: some View {
        if isCurrent, player.isLoading {
            ProgressView()
                .controlSize(.large)
                .tint(.white)
        } else if isCurrent, player.playbackError != nil {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.white)
                .shadow(radius: 3)
        } else if !isCurrent || !player.isPlaying {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.white)
                .shadow(radius: 3)
        }
    }

    private func togglePlayback() {
        Media.shared.stop()
        TelegramAudioPlayer.shared.stop()
        player.toggle(message: message, content: content, service: service)
    }
}
