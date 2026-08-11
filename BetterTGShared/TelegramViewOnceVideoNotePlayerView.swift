// TelegramViewOnceVideoNotePlayerView.swift

import SwiftUI

// MARK: - TelegramViewOnceVideoNotePlayerView

/// Keeps view-once playback outside the message row, which TDLib may replace as soon as its
/// content is opened.
struct TelegramViewOnceVideoNotePlayerView: View {
    @Bindable var player: TelegramVideoNotePlayer

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Button(action: player.toggleCurrentPlayback) {
                ZStack {
                    Circle().fill(.black)

                    if let avPlayer = player.player {
                        TelegramVideoNotePlayerSurface(player: avPlayer)
                    }

                    if player.isLoading {
                        ProgressView()
                            .controlSize(.large)
                            .tint(.white)
                    } else if player.playbackError != nil {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 52))
                            .foregroundStyle(.white)
                    } else if !player.isPlaying {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 52))
                            .foregroundStyle(.white)
                    }

                    Text(telegramClockDuration(player.currentTime))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.7), in: Capsule())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(18)
                }
                .frame(maxWidth: 420, maxHeight: 420)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(Circle())
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(player.isLoading || player.playbackError != nil)
            .accessibilityLabel(player.isPlaying ? "Pause Video Message" : "Play Video Message")
            .accessibilityValue("View once, duration \(telegramSpokenDuration(player.duration))")
            .accessibilityAddTraits(.startsMediaSession)

            VStack {
                HStack {
                    Spacer()
                    Button("Close", systemImage: "xmark", action: player.dismissPresentedViewOncePlayback)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderedProminent)
                }
                Spacer()
                if let playbackError = player.playbackError {
                    Text(playbackError)
                        .foregroundStyle(.white)
                }
            }
            .padding()
        }
        .task {
            await player.beginPresentedViewOncePlayback()
        }
        .onDisappear {
            player.dismissPresentedViewOncePlayback()
        }
        .interactiveDismissDisabled()
    }
}
