// ChatViewAlbum.swift

import AVKit
import SwiftUI
import TDLibKit
import UIKit

// MARK: - ChatViewAlbum

struct ChatViewAlbum: View {
    let album: [Message]
    let selection: Int64

    var body: some View {
        NavigationStack {
            ChatViewAlbumRootView(album: album, selection: selection)
        }
        .ignoresSafeArea()
    }
}

// MARK: - ChatViewAlbumRootView

private struct ChatViewAlbumRootView: View {
    // MARK: Lifecycle

    init(album: [Message], selection: Int64) {
        self.album = album
        _selection = State(initialValue: selection)
    }

    // MARK: Internal

    @Environment(\.dismiss) var dismiss

    let album: [Message]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selection) {
                ForEach(album) { albumMessage in
                    if case .messagePhoto(let messagePhoto) = albumMessage.content {
                        ZoomableContainer {
                            makeMessagePhoto(from: messagePhoto)
                        }
                        .tag(albumMessage.id)
                    } else if case .messageVideo(let messageVideo) = albumMessage.content {
                        ChatVideoPage(
                            messageVideo: messageVideo,
                            isSelected: selection == albumMessage.id,
                            onLoad: recordVideo,
                        )
                        .tag(albumMessage.id)
                    } else if case .messageAnimation(let messageAnimation) = albumMessage.content {
                        ChatAnimationPage(animation: messageAnimation.animation)
                            .tag(albumMessage.id)
                    }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            toolbar
                .frame(maxWidth: .infinity)
                .padding(.horizontal)
                .padding(.vertical, 10)
                .padding(.bottom, UIApplication.safeAreaInsets.bottom)
                .background(.ultraThinMaterial)
                .overlay(alignment: .top) { Divider() }
        }
    }

    // MARK: Private

    @State private var selection: Int64
    @State private var photos = [Int: String]()
    @State private var videos = [Int: String]()

    private var shareURL: URL? {
        guard let selectedMessage = album.first(where: { $0.id == selection }) else { return nil }
        let path: String?
        switch selectedMessage.content {
        case .messagePhoto(let messagePhoto):
            guard let size = messagePhoto.photo.sizes.getSize(.yBox) else { return nil }
            path = photos[size.photo.id]
        case .messageVideo(let messageVideo):
            path = videos[messageVideo.video.video.id]
        default:
            return nil
        }
        guard let path, FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(filePath: path)
    }

    private var toolbar: some View {
        HStack {
            Button("Close", systemImage: "xmark.circle.fill") {
                dismiss()
            }
            .labelStyle(.iconOnly)

            Spacer()

            if album.count > 1 {
                ChatAlbumPageControl(
                    selection: $selection,
                    messageIds: album.map(\.id),
                )
                .frame(maxWidth: 180, minHeight: 32)

                Spacer()
            }

            Button("Share", systemImage: "square.and.arrow.up.circle.fill") {
                if let shareURL {
                    showShareSheet([shareURL])
                }
            }
            .labelStyle(.iconOnly)
            .disabled(shareURL == nil)
        }
        .font(.title)
        .foregroundStyle(.white)
    }

    private func makeMessagePhoto(from messagePhoto: MessagePhoto) -> some View {
        TdImage(photo: messagePhoto.photo, size: .yBox, contentMode: .fit) { size, file in
            guard photos[size.photo.id] != file.local.path else { return }
            photos[size.photo.id] = file.local.path
        }
    }

    private func recordVideo(fileId: Int, path: String) {
        guard videos[fileId] != path else { return }
        videos[fileId] = path
    }
}

// MARK: - ChatAlbumPageControl

private struct ChatAlbumPageControl: UIViewRepresentable {
    // MARK: - Coordinator

    @MainActor final class Coordinator: NSObject {
        // MARK: Lifecycle

        init(selection: Binding<Int64>, messageIds: [Int64]) {
            self.selection = selection
            self.messageIds = messageIds
        }

        // MARK: Internal

        var selection: Binding<Int64>
        var messageIds: [Int64]

        @objc func pageChanged(_ sender: UIPageControl) {
            guard messageIds.indices.contains(sender.currentPage) else { return }
            selection.wrappedValue = messageIds[sender.currentPage]
        }
    }

    @Binding var selection: Int64

    let messageIds: [Int64]

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection, messageIds: messageIds)
    }

    func makeUIView(context: Context) -> UIPageControl {
        let pageControl = UIPageControl()
        pageControl.hidesForSinglePage = true
        pageControl.currentPageIndicatorTintColor = .white
        pageControl.pageIndicatorTintColor = UIColor.white.withAlphaComponent(0.35)
        pageControl.addTarget(
            context.coordinator,
            action: #selector(Coordinator.pageChanged(_:)),
            for: .valueChanged,
        )
        return pageControl
    }

    func updateUIView(_ pageControl: UIPageControl, context: Context) {
        context.coordinator.selection = $selection
        context.coordinator.messageIds = messageIds
        pageControl.numberOfPages = messageIds.count
        pageControl.currentPage = messageIds.firstIndex(of: selection) ?? 0
    }
}

// MARK: - ChatVideoPage

private struct ChatVideoPage: View {
    let messageVideo: MessageVideo
    let isSelected: Bool
    let onLoad: (Int, String) -> Void

    var body: some View {
        AsyncTdFile(id: messageVideo.video.video.id) { file in
            ChatVideoPlayer(
                fileURL: URL(filePath: file.local.path),
                duration: messageVideo.video.duration,
                startTimestamp: messageVideo.startTimestamp,
                isSelected: isSelected,
            )
            .onAppear { onLoad(file.id, file.local.path) }
        } placeholder: {
            ProgressView("Downloading video…")
                .accessibilityAddTraits(.updatesFrequently)
        }
    }
}

// MARK: - ChatVideoPlayer

private struct ChatVideoPlayer: View {
    // MARK: Lifecycle

    init(fileURL: URL, duration: Int, startTimestamp: Int, isSelected: Bool) {
        self.duration = duration
        self.startTimestamp = startTimestamp
        self.isSelected = isSelected
        _player = State(initialValue: AVPlayer(url: fileURL))
    }

    // MARK: Internal

    let duration: Int
    let startTimestamp: Int
    let isSelected: Bool

    var body: some View {
        VideoPlayer(player: player)
            .accessibilityLabel("Video, duration \(telegramClockDuration(duration))")
            .task(id: isSelected) {
                if isSelected {
                    if !prepared, startTimestamp > 0 {
                        await player.seek(to: CMTime(seconds: Double(startTimestamp), preferredTimescale: 600))
                    }
                    prepared = true
                    player.play()
                } else {
                    player.pause()
                }
            }
            .onDisappear { player.pause() }
    }

    // MARK: Private

    @State private var player: AVPlayer
    @State private var prepared = false
}

// MARK: - ChatAnimationPage

private struct ChatAnimationPage: View {
    let animation: TDLibKit.Animation

    var body: some View {
        AsyncTdFile(id: animation.animation.id) { file in
            ChatAnimationPlayer(fileURL: URL(filePath: file.local.path))
        } placeholder: {
            ProgressView("Downloading GIF…")
                .accessibilityAddTraits(.updatesFrequently)
        }
    }
}

// MARK: - ChatAnimationPlayer

/// Telegram GIFs are silent looping video, not real GIF files (`Animation.mimeType` is
/// "image/gif" or "video/mp4" - TDLib always hands back the latter) - `AVPlayerLooper` gives
/// gapless looping for free instead of hand-rolling a seek-to-zero-on-end observer.
private struct ChatAnimationPlayer: View {
    // MARK: Lifecycle

    init(fileURL: URL) {
        let item = AVPlayerItem(url: fileURL)
        let queuePlayer = AVQueuePlayer()
        queuePlayer.isMuted = true
        _player = State(initialValue: queuePlayer)
        _looper = State(initialValue: AVPlayerLooper(player: queuePlayer, templateItem: item))
    }

    // MARK: Internal

    var body: some View {
        VideoPlayer(player: player)
            .accessibilityLabel("GIF")
            .onAppear { player.play() }
            .onDisappear { player.pause() }
    }

    // MARK: Private

    @State private var looper: AVPlayerLooper
    @State private var player: AVQueuePlayer
}
