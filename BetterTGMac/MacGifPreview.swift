// MacGifPreview.swift

import AVKit
import SwiftUI

struct MacGifPreview: View {
    // MARK: Internal

    @Bindable var model: MacSessionModel

    let fileId: Int
    let caption: String

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("GIF")
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
                        .accessibilityLabel("GIF")
                } else if didFail {
                    ContentUnavailableView(
                        "GIF Unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text("The GIF could not be downloaded."),
                    )
                } else {
                    ProgressView("Downloading GIF…")
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
            guard let path = await model.localAnimationPath(fileId: fileId) else {
                didFail = true
                return
            }
            let url = URL(filePath: path)
            fileURL = url
            let item = AVPlayerItem(url: url)
            let queuePlayer = AVQueuePlayer()
            queuePlayer.isMuted = true
            looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
            player = queuePlayer
            queuePlayer.play()
        }
        .onDisappear { player?.pause() }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?
    @State private var fileURL: URL?
    @State private var didFail = false
}
