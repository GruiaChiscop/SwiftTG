// ChatViewAlbum.swift

import AVKit
import SwiftUI
import TDLibKit

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
                            onLoad: { fileId, path in videos[fileId] = path },
                        )
                        .tag(albumMessage.id)
                    }
                }
            }
            .tabViewStyle(.page)

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

            if let shareURL {
                Button("Share", systemImage: "square.and.arrow.up.circle.fill") {
                    showShareSheet([shareURL])
                }
                .labelStyle(.iconOnly)
            }
        }
        .font(.title)
        .foregroundStyle(.white)
    }

    private func makeMessagePhoto(from messagePhoto: MessagePhoto) -> some View {
        TdImage(photo: messagePhoto.photo, size: .yBox, contentMode: .fit) { size, file in
            withAnimation { photos[size.photo.id] = file.local.path }
        }
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
