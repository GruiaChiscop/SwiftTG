// MacVoicePlayer.swift

import AVFoundation
import Observation

/// Thin macOS wrapper around the shared `VoiceMessagePlaybackEngine` - unlike iOS's `Media`, macOS
/// needs neither `AVAudioSession` setup nor Now Playing/remote-command integration.
@MainActor @Observable final class MacVoicePlayer {
    // MARK: Lifecycle

    private init() {
        engine.onStopped = { [weak self] in self?.currentFileId = nil }
    }

    // MARK: Internal

    static let shared = MacVoicePlayer()

    private(set) var currentFileId: Int?

    var currentTime: Int { engine.currentTime }
    var isPlaying: Bool { engine.isPlaying }

    func toggle(fileId: Int, path: String, duration: Int) {
        currentFileId = fileId
        engine.toggle(path: path, duration: duration)
    }

    func seekBackward() {
        engine.seekBackward()
    }

    func seekForward() {
        engine.seekForward()
    }

    func stop() {
        engine.stop()
    }

    // MARK: Private

    @ObservationIgnored private let engine = VoiceMessagePlaybackEngine()
}
