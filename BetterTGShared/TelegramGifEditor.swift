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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Edit GIF")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                TelegramGifEditorPreview(
                    animation: animation,
                    player: player,
                    editorState: editorState,
                )

                TelegramEditorToolbar(
                    editorState: editorState,
                    addText: showTextPrompt,
                    addEmoji: showEmojiPrompt,
                    addSticker: showStickerPicker,
                )

                TelegramEditorInspector(editorState: editorState)

                if duration > 0 {
                    TelegramGifTrimControls(
                        startTime: $startTime,
                        endTime: $endTime,
                        duration: duration,
                        minimumDuration: Self.minimumDuration,
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
                    Button("Cancel", role: .cancel, action: dismissEditor)
                        .keyboardShortcut(.cancelAction)
                        .disabled(isSending)
                    Button("Send Edited GIF", systemImage: "paperplane.fill", action: exportAndSend)
                        .keyboardShortcut(.defaultAction)
                        .disabled(localURL == nil || duration == 0 || isSending)
                }
            }
            .padding()
        }
        .frame(maxWidth: 640)
        .task(id: animation.animation.id) { await load() }
        .onDisappear { player?.pause() }
        .interactiveDismissDisabled(isSending)
        .alert("Add Text", isPresented: $showsTextPrompt) {
            TextField("Text", text: $draftText)
            Button("Add", action: addText)
                .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) { draftText = "" }
        }
        .alert("Add Emoji", isPresented: $showsEmojiPrompt) {
            TextField("Emoji", text: $draftEmoji)
            Button("Add", action: addEmoji)
                .disabled(draftEmoji.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) { draftEmoji = "" }
        }
        .sheet(isPresented: $showsStickerPicker) {
            TelegramEditorStickerPicker(service: service, onSelected: addSticker)
        }
    }

    // MARK: Private

    private static let minimumDuration = 0.5

    @AccessibilityFocusState private var errorIsFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var editorState = TelegramMediaEditorState()
    @State private var localURL: URL?
    @State private var player: AVPlayer?
    @State private var loadedCanvasSize: CGSize?
    @State private var duration = 0.0
    @State private var startTime = 0.0
    @State private var endTime = 0.0
    @State private var caption = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var showsTextPrompt = false
    @State private var showsEmojiPrompt = false
    @State private var showsStickerPicker = false
    @State private var draftText = ""
    @State private var draftEmoji = ""

    private var canvasSize: CGSize {
        if let loadedCanvasSize {
            loadedCanvasSize
        } else if animation.width > 0, animation.height > 0 {
            CGSize(width: animation.width, height: animation.height)
        } else {
            CGSize(width: 512, height: 512)
        }
    }

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
            editorState.timelineDuration = loadedDuration
            await loadCanvasSize(from: asset)
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
                let timeRange = CMTimeRange(
                    start: CMTime(seconds: startTime, preferredTimescale: 600),
                    duration: CMTime(seconds: endTime - startTime, preferredTimescale: 600),
                )
                try await TelegramGifCompositor.export(
                    asset: asset,
                    snapshot: editorState.snapshot,
                    canvasSize: canvasSize,
                    timeRange: timeRange,
                    outputURL: outputURL,
                )
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

    private func showTextPrompt() {
        draftText = ""
        showsTextPrompt = true
    }

    private func showEmojiPrompt() {
        draftEmoji = ""
        showsEmojiPrompt = true
    }

    private func showStickerPicker() {
        showsStickerPicker = true
    }

    private func addText() {
        editorState.addText(draftText)
        draftText = ""
    }

    private func addEmoji() {
        editorState.addEmoji(draftEmoji)
        draftEmoji = ""
    }

    private func addSticker(_ sticker: TelegramStickerOverlay) {
        editorState.addSticker(sticker)
    }

    private func dismissEditor() {
        dismiss()
    }

    @MainActor private func loadCanvasSize(from asset: AVAsset) async {
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let naturalSize = try? await track.load(.naturalSize),
              let preferredTransform = try? await track.load(.preferredTransform)
        else { return }
        let transformedSize = naturalSize.applying(preferredTransform)
        let width = abs(transformedSize.width)
        let height = abs(transformedSize.height)
        if width > 0, height > 0 {
            loadedCanvasSize = CGSize(width: width, height: height)
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
