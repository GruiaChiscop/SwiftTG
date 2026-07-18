// MacVoiceMessageContent.swift

import SwiftUI
import TDLibKit

struct MacVoiceMessageContent: View {
    // MARK: Internal

    let caption: FormattedText
    let voiceNote: VoiceNote
    let path: String?

    @Bindable var player: MacVoicePlayer

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button("Back 5 Seconds", systemImage: "gobackward.5") {
                    player.seekBackward()
                }
                .labelStyle(.iconOnly)
                .disabled(!isCurrent)

                Button(
                    isPlaying ? "Pause Voice Message" : "Play Voice Message",
                    systemImage: isPlaying
                        ? "pause.fill"
                        : "play.fill",
                ) {
                    guard let path else { return }
                    TelegramAudioPlayer.shared.stop()
                    player.toggle(fileId: voiceNote.voice.id, path: path, duration: voiceNote.duration)
                }
                .labelStyle(.iconOnly)
                .disabled(path == nil)

                Button("Forward 5 Seconds", systemImage: "goforward.5") {
                    player.seekForward()
                }
                .labelStyle(.iconOnly)
                .disabled(!isCurrent)

                ProgressView(value: Double(elapsed), total: Double(max(1, voiceNote.duration)))
                    .frame(minWidth: 100)
            }
            .accessibilityHidden(true)

            Text("\(telegramClockDuration(elapsed)) / \(telegramClockDuration(voiceNote.duration))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
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
        player.currentFileId == voiceNote.voice.id
    }

    private var isPlaying: Bool {
        isCurrent && player.isPlaying
    }
}
