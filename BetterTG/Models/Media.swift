// Media.swift

import AVFoundation
import Observation

/// Thin iOS wrapper around the shared `VoiceMessagePlaybackEngine`, adding audio session setup
/// around it. macOS's `MacVoicePlayer` wraps the same engine without one, since it doesn't apply
/// there.
///
/// Deliberately has no Now Playing/`MPRemoteCommandCenter` integration - matching Telegram-iOS's
/// own `MediaManager`, which only surfaces music tracks there, never voice messages. Every
/// transition of that Control Center/lock-screen surface (appearing *or* disappearing) makes
/// VoiceOver play its own "layout changed" cue, which is audible on every single recording start
/// once a voice message has ever played in the session (`VoiceRecordingController` stops any
/// current playback before recording, and stopping playback is what tears the surface down) -
/// there's no way to only sometimes have that surface without sometimes paying for the transition.
@Observable final class Media: @unchecked Sendable {
    // MARK: Lifecycle

    init() {
        self.engine = MainActor.assumeIsolated { VoiceMessagePlaybackEngine() }
        MainActor.assumeIsolated {
            engine.trace = { voicePlaybackTrace($0) }
            engine.onWillPlay = { [weak self] in self?.setAudioSessionPlayback() ?? false }
        }
    }

    // MARK: Internal

    static let shared = Media()

    var savedMediaPath: String { MainActor.assumeIsolated { engine.currentPath } ?? "" }
    var isPlaying: Bool { MainActor.assumeIsolated { engine.isPlaying } }
    var currentTime: Int32 { Int32(MainActor.assumeIsolated { engine.currentTime }) }

    func stop() {
        MainActor.assumeIsolated { engine.stop() }
    }

    func onChatDismiss() {
        MainActor.assumeIsolated { engine.pause() }
    }

    func seekForward() {
        MainActor.assumeIsolated { engine.seekForward() }
    }

    func seekBackward() {
        MainActor.assumeIsolated { engine.seekBackward() }
    }

    func toggle(with path: String, duration: Int, allowsSeeking: Bool = true) {
        MainActor.assumeIsolated {
            engine.toggle(path: path, duration: duration, allowsSeeking: allowsSeeking)
        }
    }

    func setAudioSessionRecord() {
        do {
            // No `.mixWithOthers`, ever, for any reason - letting other audio (music, etc.) keep
            // playing through the speaker while the microphone is recording risks it bleeding into
            // the recorded message itself.
            let options: AVAudioSession.CategoryOptions = [
                .allowBluetoothHFP,
                .allowBluetoothA2DP,
                .defaultToSpeaker,
            ]
            try audioSession.setCategory(.playAndRecord, mode: .default, options: options)
            try audioSession.setActive(true)
        } catch {
            log("Error setting audioSessionRecord: \(error)")
        }
    }

    func endAudioSessionRecord() {
        do {
            try audioSession.setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            log("Error ending audioSessionRecord: \(error)")
        }
    }

    // MARK: Private

    @ObservationIgnored private let engine: VoiceMessagePlaybackEngine
    private let audioSession = AVAudioSession.sharedInstance()

    private func setAudioSessionPlayback() -> Bool {
        do {
            try audioSession.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try audioSession.setActive(true)
            return true
        } catch {
            log("Error setting audioSessionPlayback: \(error)")
            return false
        }
    }
}
