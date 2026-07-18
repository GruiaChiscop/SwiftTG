// TelegramAudioPlayer.swift

import AVFoundation
import Observation
import SwiftUI
import TDLibKit

@MainActor @Observable final class TelegramAudioPlayer {
    // MARK: Lifecycle

    private init() {}

    deinit {
        timeControlObservation?.invalidate()
        if let timeObserver {
            player?.removeTimeObserver(timeObserver)
        }
        if let playbackFinishedObserver {
            NotificationCenter.default.removeObserver(playbackFinishedObserver)
        }
        resourceLoader?.cancel()
        fallbackTask?.cancel()
    }

    // MARK: Internal

    static let shared = TelegramAudioPlayer()

    var currentFileId: Int?
    var currentTime = 0
    var downloadedBytes: Int64 = 0
    var totalBytes: Int64 = 0
    var isBuffering = false
    var isDownloaded = false
    var isPlaying = false
    var playbackError: String?
    private(set) var playlist = [Audio]()

    var canPlayNext: Bool {
        guard let currentPlaylistIndex else { return false }
        return playlist.indices.contains(currentPlaylistIndex + 1)
    }

    var canPlayPrevious: Bool {
        guard let currentPlaylistIndex else { return false }
        return currentPlaylistIndex > 0 || currentTime > 3
    }

    var currentAudio: Audio? {
        guard let currentFileId else { return nil }
        return playlist.first { $0.audio.id == currentFileId }
    }

    func toggle(
        audio: Audio,
        service: any TelegramService,
        playlist: [Audio] = [],
    ) {
        configurePlaylist(playlist, current: audio)
        self.service = service
        if currentFileId != audio.audio.id {
            prepare(audio: audio, service: service)
            play()
        } else if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func togglePlayback() {
        if isPlaying {
            pause()
        } else {
            if duration > 0, currentTime >= duration {
                seek(to: 0)
            }
            play()
        }
    }

    func playNext() {
        guard let currentPlaylistIndex,
              playlist.indices.contains(currentPlaylistIndex + 1),
              let service
        else { return }
        prepare(audio: playlist[currentPlaylistIndex + 1], service: service)
        play()
    }

    func playPrevious() {
        if currentSeconds > 3 {
            seek(to: 0)
            return
        }
        guard let currentPlaylistIndex,
              currentPlaylistIndex > 0,
              let service
        else {
            seek(to: 0)
            return
        }
        prepare(audio: playlist[currentPlaylistIndex - 1], service: service)
        play()
    }

    func seekBackward() {
        seek(to: max(0, currentSeconds - 5))
    }

    func seekForward() {
        seek(to: min(Double(duration), currentSeconds + 5))
    }

    func stop() {
        resetPlayback()
        playlist.removeAll()
        service = nil
    }

    // MARK: Private

    @ObservationIgnored private var duration = 0
    @ObservationIgnored private var fallbackTask: Task<Void, Never>?
    @ObservationIgnored private var playbackFinishedObserver: NSObjectProtocol?
    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var resourceLoader: TDLibAudioResourceLoader?
    @ObservationIgnored private var service: (any TelegramService)?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var timeControlObservation: NSKeyValueObservation?

    private var currentPlaylistIndex: Int? {
        guard let currentFileId else { return nil }
        return playlist.firstIndex { $0.audio.id == currentFileId }
    }

    private var currentSeconds: Double {
        guard let seconds = player?.currentTime().seconds, seconds.isFinite else { return Double(currentTime) }
        return seconds
    }

    private func resetPlayback() {
        player?.pause()
        removePlaybackObservers()
        resourceLoader?.cancel()
        resourceLoader = nil
        fallbackTask?.cancel()
        fallbackTask = nil
        player = nil
        currentFileId = nil
        currentTime = 0
        downloadedBytes = 0
        totalBytes = 0
        isBuffering = false
        isDownloaded = false
        isPlaying = false
        playbackError = nil
        duration = 0
    }

    private func prepare(audio: Audio, service: any TelegramService) {
        resetPlayback()
        currentFileId = audio.audio.id
        duration = audio.duration
        updateDownloadState(audio.audio)

        if audio.audio.local.isDownloadingCompleted, !audio.audio.local.path.isEmpty {
            configurePlayer(
                item: AVPlayerItem(url: URL(filePath: audio.audio.local.path)),
                fileId: audio.audio.id,
            )
            return
        }

        guard max(audio.audio.size, audio.audio.expectedSize) > 0 else {
            downloadAndPrepareFallback(audio: audio, service: service, autoplay: true)
            return
        }

        let loader = TDLibAudioResourceLoader(
            file: audio.audio,
            mimeType: audio.mimeType,
            duration: audio.duration,
            service: service,
            onFileUpdate: { [weak self] file in
                Task { @MainActor [weak self] in
                    guard let self, currentFileId == file.id else { return }
                    updateDownloadState(file)
                }
            },
            onFailure: { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, currentFileId == audio.audio.id else { return }
                    downloadAndPrepareFallback(audio: audio, service: service, autoplay: isPlaying)
                }
            },
        )
        resourceLoader = loader
        let asset = AVURLAsset(url: loader.assetURL)
        asset.resourceLoader.setDelegate(loader, queue: loader.queue)
        configurePlayer(item: AVPlayerItem(asset: asset), fileId: audio.audio.id)
    }

    private func configurePlayer(item: AVPlayerItem, fileId: Int) {
        let player = AVPlayer(playerItem: item)
        self.player = player
        timeControlObservation = player.observe(\.timeControlStatus, options: [
            .initial,
            .new,
        ]) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                guard let self, currentFileId == fileId else { return }
                isBuffering = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
            }
        }
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
                guard self?.currentFileId == fileId else { return }
                if self?.canPlayNext == true {
                    self?.playNext()
                } else {
                    self?.isPlaying = false
                    self?.isBuffering = false
                    self?.currentTime = self?.duration ?? 0
                }
            }
        }
    }

    private func configurePlaylist(_ proposedPlaylist: [Audio], current audio: Audio) {
        var unique = [Audio]()
        var seenFileIds = Set<Int>()
        for item in proposedPlaylist where seenFileIds.insert(item.audio.id).inserted {
            unique.append(item)
        }
        if unique.contains(where: { $0.audio.id == audio.audio.id }) {
            playlist = unique
        } else {
            playlist = [audio]
        }
    }

    private func play() {
        guard let player else { return }
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [])
        try? session.setActive(true)
        #endif
        player.play()
        isPlaying = true
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

    private func downloadAndPrepareFallback(
        audio: Audio,
        service: any TelegramService,
        autoplay: Bool,
    ) {
        guard fallbackTask == nil else { return }
        let fileId = audio.audio.id
        let shouldPlay = autoplay
        player?.pause()
        removePlaybackObservers()
        resourceLoader?.cancel(download: false)
        resourceLoader = nil
        player = nil
        isBuffering = true
        fallbackTask = Task { [weak self] in
            do {
                let file = try await service.downloadFile(
                    fileId: fileId,
                    limit: 0,
                    offset: 0,
                    priority: 32,
                    synchronous: true,
                )
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    guard let self, currentFileId == fileId else { return }
                    fallbackTask = nil
                    updateDownloadState(file)
                    guard file.local.isDownloadingCompleted, !file.local.path.isEmpty else {
                        playbackError = "Audio download failed"
                        isBuffering = false
                        isPlaying = false
                        return
                    }
                    configurePlayer(
                        item: AVPlayerItem(url: URL(filePath: file.local.path)),
                        fileId: fileId,
                    )
                    if shouldPlay {
                        play()
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    guard let self, currentFileId == fileId else { return }
                    fallbackTask = nil
                    playbackError = error.localizedDescription
                    isBuffering = false
                    isPlaying = false
                }
            }
        }
    }

    private func updateDownloadState(_ file: File) {
        downloadedBytes = file.local.downloadedSize
        totalBytes = max(file.size, file.expectedSize)
        isDownloaded = file.local.isDownloadingCompleted
    }

    private func removePlaybackObservers() {
        timeControlObservation?.invalidate()
        timeControlObservation = nil
        if let timeObserver {
            player?.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        if let playbackFinishedObserver {
            NotificationCenter.default.removeObserver(playbackFinishedObserver)
            self.playbackFinishedObserver = nil
        }
    }
}

// MARK: - TelegramAudioPlayerBar

struct TelegramAudioPlayerBar: View {
    @State private var player = TelegramAudioPlayer.shared

    var body: some View {
        if let audio = player.currentAudio {
            VStack(spacing: 0) {
                ProgressView(
                    value: Double(player.currentTime),
                    total: Double(max(1, audio.duration)),
                )
                .accessibilityLabel("Playback progress")
                .accessibilityValue(
                    "\(telegramClockDuration(player.currentTime)) of \(telegramClockDuration(audio.duration))",
                )

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(telegramAudioTitle(audio))
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        if !audio.performer.isEmpty {
                            Text(audio.performer)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button("Previous", systemImage: "backward.fill") {
                        player.playPrevious()
                    }
                    .labelStyle(.iconOnly)
                    .disabled(!player.canPlayPrevious)

                    Button(
                        player.isPlaying ? "Pause" : "Play",
                        systemImage: player.isPlaying ? "pause.fill" : "play.fill",
                    ) {
                        player.togglePlayback()
                    }
                    .labelStyle(.iconOnly)

                    Button("Next", systemImage: "forward.fill") {
                        player.playNext()
                    }
                    .labelStyle(.iconOnly)
                    .disabled(!player.canPlayNext)

                    Button("Close Player", systemImage: "xmark") {
                        player.stop()
                    }
                    .labelStyle(.iconOnly)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(.bar)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Audio player")
        }
    }
}
