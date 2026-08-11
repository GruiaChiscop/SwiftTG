// TelegramVideoNotePlayback.swift

@preconcurrency import AVFoundation
import Observation
import SwiftUI
@preconcurrency import TDLibKit

// MARK: - TelegramVideoNotePresentation

struct TelegramVideoNotePresentation: Equatable {
    // MARK: Lifecycle

    init(_ content: MessageVideoNote, isOutgoing: Bool) {
        self.fileId = content.videoNote.video.id
        self.thumbnailFileId = content.videoNote.thumbnail?.file.id
        self.duration = max(0, content.videoNote.duration)
        self.isSecret = content.isSecret
        self.isViewed = content.isViewed
        self.isOutgoing = isOutgoing
    }

    // MARK: Internal

    let fileId: Int
    let thumbnailFileId: Int?
    let duration: Int
    let isSecret: Bool
    let isViewed: Bool
    let isOutgoing: Bool

    var accessibilityDescription: String {
        [isOutgoing ? "Your video message" : "Video message", accessibilityDetails]
            .joined(separator: ", ")
    }

    /// Static details are kept separate from live playback progress so a message row can expose
    /// a stable accessibility element while its visual timer continues to update.
    var accessibilityDetails: String {
        var parts = [String]()
        if isSecret {
            parts.append("view once")
        }
        parts.append("duration \(telegramSpokenDuration(duration))")
        return parts.joined(separator: ", ")
    }
}

// MARK: - TelegramVideoNotePlayer

/// One shared player keeps video messages mutually exclusive across rows and mirrors Telegram's
/// single active media session. Full files are downloaded only after explicit activation; merely
/// scrolling a chat therefore doesn't start dozens of video downloads or decoders.
@MainActor @Observable final class TelegramVideoNotePlayer {
    // MARK: Lifecycle

    private init() {}

    deinit {
        MainActor.assumeIsolated {
            resetPlayback()
        }
    }

    // MARK: Internal

    static let shared = TelegramVideoNotePlayer()

    private(set) var currentFileId: Int?
    private(set) var currentTime = 0
    private(set) var duration = 0
    private(set) var isLoading = false
    private(set) var isPlaying = false
    private(set) var playbackError: String?
    private(set) var player: AVPlayer?

    func toggle(videoNote: VideoNote, service: any TelegramService) {
        let file = videoNote.video
        if currentFileId == file.id {
            if isLoading {
                return
            }
            if isPlaying {
                pause()
            } else {
                if duration > 0, currentTime >= duration {
                    seek(to: 0)
                }
                play()
            }
            return
        }

        resetPlayback()
        currentFileId = file.id
        duration = max(0, videoNote.duration)
        if file.local.isDownloadingCompleted, !file.local.path.isEmpty {
            configurePlayer(url: URL(filePath: file.local.path), fileId: file.id)
            play()
        } else {
            downloadAndPlay(fileId: file.id, service: service)
        }
    }

    func pauseIfCurrent(fileId: Int) {
        guard currentFileId == fileId else { return }
        pause()
    }

    func stop() {
        resetPlayback()
    }

    // MARK: Private

    @ObservationIgnored private var downloadTask: Task<Void, Never>?
    @ObservationIgnored private var playbackFinishedObserver: NSObjectProtocol?
    @ObservationIgnored private var timeObserver: Any?

    private func configurePlayer(url: URL, fileId: Int) {
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        self.player = player
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main,
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self, currentFileId == fileId, time.seconds.isFinite else { return }
                currentTime = max(0, Int(time.seconds))
            }
        }
        playbackFinishedObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main,
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, currentFileId == fileId else { return }
                isPlaying = false
                currentTime = duration
            }
        }
    }

    private func downloadAndPlay(fileId: Int, service: any TelegramService) {
        isLoading = true
        downloadTask = Task { [weak self] in
            do {
                let file = try await service.downloadFile(
                    fileId: fileId,
                    limit: 0,
                    offset: 0,
                    priority: 32,
                    synchronous: true,
                )
                try Task.checkCancellation()
                guard file.local.isDownloadingCompleted, !file.local.path.isEmpty else {
                    throw TelegramVideoNotePlaybackError.downloadFailed
                }
                guard let self, currentFileId == fileId else { return }
                downloadTask = nil
                isLoading = false
                configurePlayer(url: URL(filePath: file.local.path), fileId: fileId)
                play()
            } catch is CancellationError {
                // A different video message replaced this one.
            } catch {
                guard let self, currentFileId == fileId else { return }
                downloadTask = nil
                isLoading = false
                isPlaying = false
                playbackError = "Video message couldn't be downloaded."
            }
        }
    }

    private func play() {
        guard let player else { return }
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        // An exclusive playback session interrupts VoiceOver mid-speech and makes it restore its
        // context from the top of the conversation. Mixing preserves VoiceOver's audio and focus.
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true, options: [])
        #endif
        player.play()
        isPlaying = true
        playbackError = nil
    }

    private func pause() {
        player?.pause()
        isPlaying = false
    }

    private func seek(to seconds: Double) {
        guard let player else { return }
        let target = max(0, min(seconds, Double(duration)))
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        currentTime = Int(target)
    }

    private func resetPlayback() {
        downloadTask?.cancel()
        downloadTask = nil
        player?.pause()
        if let timeObserver {
            player?.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        if let playbackFinishedObserver {
            NotificationCenter.default.removeObserver(playbackFinishedObserver)
            self.playbackFinishedObserver = nil
        }
        player = nil
        currentFileId = nil
        currentTime = 0
        duration = 0
        isLoading = false
        isPlaying = false
        playbackError = nil
    }
}

// MARK: - TelegramVideoNotePlayerSurface

struct TelegramVideoNotePlayerSurface: View {
    let player: AVPlayer

    var body: some View {
        TelegramPlatformVideoNotePlayer(player: player)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

#if os(iOS)
private struct TelegramPlatformVideoNotePlayer: UIViewRepresentable {
    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }

        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    let player: AVPlayer

    func makeUIView(context _: Context) -> PlayerView {
        let view = PlayerView()
        view.playerLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PlayerView, context _: Context) {
        view.playerLayer.player = player
    }
}
#elseif os(macOS)
private struct TelegramPlatformVideoNotePlayer: NSViewRepresentable {
    final class PlayerView: NSView {
        // MARK: Lifecycle

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer = playerLayer
            playerLayer.videoGravity = .resizeAspectFill
        }

        @available(*, unavailable) required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        // MARK: Internal

        let playerLayer = AVPlayerLayer()

        override func layout() {
            super.layout()
            playerLayer.frame = bounds
        }
    }

    let player: AVPlayer

    func makeNSView(context _: Context) -> PlayerView {
        PlayerView()
    }

    func updateNSView(_ view: PlayerView, context _: Context) {
        view.playerLayer.player = player
    }
}
#endif

// MARK: - TelegramVideoNotePlaybackError

private enum TelegramVideoNotePlaybackError: Swift.Error {
    case downloadFailed
}
