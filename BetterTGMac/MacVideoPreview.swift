// MacVideoPreview.swift

import AVKit
import SwiftUI

struct MacVideoPreview: View {
    // MARK: Internal

    @Bindable var model: MacSessionModel

    let fileId: Int
    let caption: String
    let duration: Int
    let startTimestamp: Int

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Video")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Close", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
                    .keyboardShortcut(.cancelAction)
            }

            Group {
                if let player {
                    VideoPlayer(player: player)
                        .accessibilityLabel("Video, duration \(telegramClockDuration(duration))")
                } else if didFail {
                    ContentUnavailableView(
                        "Video Unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text("The video could not be downloaded."),
                    )
                } else {
                    ProgressView("Downloading video…")
                        .accessibilityAddTraits(.updatesFrequently)
                }
            }
            .frame(minWidth: 640, minHeight: 360)

            if !caption.isEmpty {
                Text(caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }

            if let fileURL {
                HStack {
                    Spacer()
                    Button("Open in Default App", systemImage: "arrow.up.forward.app") {
                        NSWorkspace.shared.open(fileURL)
                    }
                }
            }
        }
        .padding(16)
        .frame(minWidth: 680, minHeight: 480)
        .task(id: fileId) {
            guard let path = await model.localVideoPath(fileId: fileId) else {
                didFail = true
                return
            }
            let url = URL(filePath: path)
            fileURL = url
            let player = AVPlayer(url: url)
            self.player = player
            if startTimestamp > 0 {
                await player.seek(to: CMTime(seconds: Double(startTimestamp), preferredTimescale: 600))
            }
            player.play()
        }
        .onDisappear { player?.pause() }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var fileURL: URL?
    @State private var didFail = false
}
