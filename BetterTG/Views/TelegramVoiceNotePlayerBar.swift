// TelegramVoiceNotePlayerBar.swift

import SwiftUI

/// Mirrors `TelegramAudioPlayerBar`'s bottom-bar pattern, but for a voice note played through
/// `Media` rather than a music track through `TelegramAudioPlayer` - the two engines are
/// independent (`MessageVoiceNoteView` stops the other one when starting its own kind), so each
/// gets its own bar rather than one trying to represent both. Skip/speed live here now instead of
/// in the message bubble, matching Telegram-iOS's own bubble (which has neither) - VoiceOver users
/// still reach them from the message itself via its accessibility actions regardless of whether
/// this bar is showing.
struct TelegramVoiceNotePlayerBar: View {
    // MARK: Internal

    var body: some View {
        if !media.savedMediaPath.isEmpty {
            VStack(spacing: 0) {
                ProgressView(
                    value: Double(media.currentTime),
                    total: Double(max(1, media.duration)),
                )
                .accessibilityLabel("Playback progress")
                .accessibilityValue(
                    "\(telegramClockDuration(Int(media.currentTime))) of \(telegramClockDuration(media.duration))",
                )

                HStack(spacing: 12) {
                    Text("Voice Message")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button("Skip Backward", systemImage: "gobackward.5") {
                        media.seekBackward()
                    }
                    .labelStyle(.iconOnly)
                    .disabled(!media.allowsSeeking)

                    Button(
                        media.isPlaying ? "Pause" : "Play",
                        systemImage: media.isPlaying ? "pause.fill" : "play.fill",
                    ) {
                        media.togglePlayPause()
                    }
                    .labelStyle(.iconOnly)

                    Button("Skip Forward", systemImage: "goforward.5") {
                        media.seekForward()
                    }
                    .labelStyle(.iconOnly)
                    .disabled(!media.allowsSeeking)

                    Button(TelegramVoicePlaybackRateSettings.title(for: media.playbackRate)) {
                        media.cyclePlaybackRate()
                    }
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .accessibilityLabel("Playback Speed")
                    .accessibilityValue(TelegramVoicePlaybackRateSettings.title(for: media.playbackRate))

                    Button("Close Player", systemImage: "xmark") {
                        media.stop()
                    }
                    .labelStyle(.iconOnly)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(.bar)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Voice message player")
        }
    }

    // MARK: Private

    @State private var media = Media.shared
}
