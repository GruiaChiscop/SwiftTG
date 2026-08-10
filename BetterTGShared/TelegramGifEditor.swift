// TelegramGifEditor.swift

import AVKit
import SwiftUI
import TDLibKit

// MARK: - TelegramGifEditor

struct TelegramGifEditor: View {
    // MARK: Internal

    let animation: TDLibKit.Animation
    let service: any TelegramService
    let onSend: @MainActor (URL, String, Int) async throws -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit GIF")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            Group {
                if let player {
                    VideoPlayer(player: player)
                } else {
                    ProgressView("Loading GIF")
                }
            }
            .frame(minHeight: 180, maxHeight: 260)
            .clipShape(.rect(cornerRadius: 12))

            if duration > 0 {
                LabeledContent("Start") {
                    Text(startTime, format: .number.precision(.fractionLength(1)))
                        .monospacedDigit()
                }
                Slider(
                    value: $startTime,
                    in: 0...max(0, endTime - Self.minimumDuration),
                    step: 0.1,
                )

                LabeledContent("End") {
                    Text(endTime, format: .number.precision(.fractionLength(1)))
                        .monospacedDigit()
                }
                Slider(
                    value: $endTime,
                    in: min(duration, startTime + Self.minimumDuration)...duration,
                    step: 0.1,
                )
            }

            TextField("Add a caption…", text: $caption, axis: .vertical)
                .lineLimit(2...5)

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .accessibilityFocused($errorIsFocused)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isSending)
                Button("Send Edited GIF", systemImage: "paperplane.fill", action: exportAndSend)
                    .keyboardShortcut(.defaultAction)
                    .disabled(localURL == nil || duration == 0 || isSending)
            }
        }
        .padding()
        .frame(maxWidth: 440)
        .task(id: animation.animation.id) { await load() }
        .onDisappear { player?.pause() }
        .interactiveDismissDisabled(isSending)
    }

    // MARK: Private

    private static let minimumDuration = 0.5

    @AccessibilityFocusState private var errorIsFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var localURL: URL?
    @State private var player: AVPlayer?
    @State private var duration = 0.0
    @State private var startTime = 0.0
    @State private var endTime = 0.0
    @State private var caption = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    @MainActor private func load() async {
        do {
            let file = try await service.downloadFile(
                fileId: animation.animation.id,
                limit: 0,
                offset: 0,
                priority: 32,
                synchronous: true,
            )
            guard file.local.isDownloadingCompleted, !file.local.path.isEmpty else {
                throw TelegramGifEditorError.downloadFailed
            }
            let url = URL(filePath: file.local.path)
            let asset = AVURLAsset(url: url)
            let loadedDuration = try await asset.load(.duration).seconds
            guard loadedDuration.isFinite, loadedDuration >= Self.minimumDuration else {
                throw TelegramGifEditorError.invalidDuration
            }
            localURL = url
            duration = loadedDuration
            endTime = loadedDuration
            let player = AVPlayer(url: url)
            player.isMuted = true
            self.player = player
            player.play()
        } catch is CancellationError {
            return
        } catch {
            show(error)
        }
    }

    private func exportAndSend() {
        guard let localURL, !isSending else { return }
        isSending = true
        errorMessage = nil
        errorIsFocused = false
        Task {
            let outputURL = URL.temporaryDirectory.appending(path: "bettertg-edited-gif-\(UUID().uuidString).mp4")
            do {
                let asset = AVURLAsset(url: localURL)
                guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough)
                else {
                    throw TelegramGifEditorError.exportUnavailable
                }
                exporter.timeRange = CMTimeRange(
                    start: CMTime(seconds: startTime, preferredTimescale: 600),
                    duration: CMTime(seconds: endTime - startTime, preferredTimescale: 600),
                )
                try await exporter.export(to: outputURL, as: .mp4)
                try await onSend(outputURL, caption, Int((endTime - startTime).rounded(.up)))
                try? FileManager.default.removeItem(at: outputURL)
                dismiss()
            } catch {
                try? FileManager.default.removeItem(at: outputURL)
                show(error)
                isSending = false
            }
        }
    }

    @MainActor private func show(_ error: any Swift.Error) {
        errorMessage = telegramErrorDescription(error)
        Task { @MainActor in
            await Task.yield()
            errorIsFocused = true
        }
    }
}
