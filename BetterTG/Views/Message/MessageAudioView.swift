// MessageAudioView.swift

import SwiftUI
import TDLibKit

struct MessageAudioView: View {
    // MARK: Internal

    let audio: Audio
    let playlist: [Audio]

    @State var player = TelegramAudioPlayer.shared

    var body: some View {
        audioView
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .onReceive(service.filePublisher(fileId: audio.audio.id)) { file in
                currentFile = file
            }
            .accessibilityHidden(true)
    }

    // MARK: Private

    @State private var currentFile: File?

    private let service: any TelegramService = TDLib.shared.service

    private var elapsed: Int {
        isCurrent ? player.currentTime : 0
    }

    private var isCurrent: Bool {
        player.currentFileId == audio.audio.id
    }

    private var isPlaying: Bool {
        isCurrent && player.isPlaying
    }

    private var isBuffering: Bool {
        isCurrent && player.isBuffering
    }

    private var displayedFile: File {
        currentFile ?? audio.audio
    }

    private var statusText: String {
        if isCurrent, let error = player.playbackError {
            return error
        }
        if isBuffering {
            let total = max(1, player.totalBytes)
            let percent = Int(Double(player.downloadedBytes) / Double(total) * 100)
            return "Buffering \(min(100, max(0, percent)))%"
        }
        if isCurrent {
            return "\(telegramClockDuration(elapsed)) / \(telegramClockDuration(audio.duration))"
        }
        let size = ByteCountFormatter.string(
            fromByteCount: max(displayedFile.size, displayedFile.expectedSize),
            countStyle: .file,
        )
        return "\(telegramClockDuration(audio.duration)) · \(size)"
    }

    private var audioView: some View {
        HStack(spacing: 10) {
            Button {
                Media.shared.stop()
                player.toggle(audio: audio, service: service, playlist: playlist)
            } label: {
                albumCover
            }

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
                Text(statusText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 150, alignment: .leading)

            VStack(spacing: 4) {
                Button("Back 5 Seconds", systemImage: "gobackward.5") {
                    player.seekBackward()
                }
                Button("Forward 5 Seconds", systemImage: "goforward.5") {
                    player.seekForward()
                }
            }
            .labelStyle(.iconOnly)
            .disabled(!isCurrent)
        }
    }

    private var albumCover: some View {
        ZStack {
            if let thumbnail = audio.albumCoverThumbnail {
                AsyncTdImage(id: thumbnail.file.id, maxPixelSize: 96, service: service) { image, _ in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    coverPlaceholder
                }
            } else {
                coverPlaceholder
            }

            if isBuffering {
                ProgressView()
                    .tint(.white)
            } else {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
            }
        }
        .frame(width: 42, height: 42)
        .background(Color.gray6, in: Circle())
        .clipShape(Circle())
    }

    private var coverPlaceholder: some View {
        Circle()
            .fill(Color.gray6)
            .overlay {
                Image(systemName: "music.note")
                    .foregroundStyle(.white.opacity(0.65))
            }
    }
}
