// MacAudioMessageContent.swift

import SwiftUI
import TDLibKit

struct MacAudioMessageContent: View {
    // MARK: Internal

    let audio: Audio
    let caption: FormattedText
    let playlist: [Audio]
    let service: any TelegramService

    @Bindable var player: TelegramAudioPlayer

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button(
                    isPlaying ? "Pause Audio" : "Play Audio",
                    systemImage: isPlaying ? "pause.fill" : "play.fill",
                ) {
                    MacVoicePlayer.shared.stop()
                    player.toggle(audio: audio, service: service, playlist: playlist)
                }
                .labelStyle(.iconOnly)

                VStack(alignment: .leading, spacing: 3) {
                    Text(telegramAudioTitle(audio))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if !audio.performer.isEmpty {
                        Text(audio.performer)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    ProgressView(value: Double(elapsed), total: Double(max(1, audio.duration)))
                        .frame(minWidth: 140)
                    Text(statusText)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Button("Back 5 Seconds", systemImage: "gobackward.5") {
                    player.seekBackward()
                }
                .labelStyle(.iconOnly)
                .disabled(!isCurrent)

                Button("Forward 5 Seconds", systemImage: "goforward.5") {
                    player.seekForward()
                }
                .labelStyle(.iconOnly)
                .disabled(!isCurrent)
            }
            .accessibilityHidden(true)
            if !caption.text.isEmpty {
                MacFormattedTextView(formattedText: caption)
            }
        }
    }

    // MARK: Private

    private var elapsed: Int {
        isCurrent ? player.currentTime : 0
    }

    private var isCurrent: Bool {
        player.currentFileId == audio.audio.id
    }

    private var isPlaying: Bool {
        isCurrent && player.isPlaying
    }

    private var statusText: String {
        if isCurrent, let error = player.playbackError {
            return error
        }
        if isCurrent, player.isBuffering {
            let total = max(1, player.totalBytes)
            let percent = Int(Double(player.downloadedBytes) / Double(total) * 100)
            return "Buffering \(min(100, max(0, percent)))%"
        }
        return "\(telegramClockDuration(elapsed)) / \(telegramClockDuration(audio.duration))"
    }
}
