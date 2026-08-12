// Media.swift

import AVFoundation
import MediaPlayer
import Observation

/// Thin iOS wrapper around the shared `VoiceMessagePlaybackEngine`, adding audio session setup
/// and Now Playing/remote-command-center integration around it. macOS's `MacVoicePlayer` wraps
/// the same engine without either, since neither applies there.
@Observable final class Media: @unchecked Sendable {
    // MARK: Lifecycle

    init() {
        self.engine = MainActor.assumeIsolated { VoiceMessagePlaybackEngine() }
        setCommandCenterControls()
        MainActor.assumeIsolated {
            engine.trace = { voicePlaybackTrace($0) }
            engine.onWillPlay = { [weak self] in self?.setAudioSessionPlayback() ?? false }
            engine.onPlayStarted = { [weak self] in self?.setNowPlaying() }
            engine.onTick = { [weak self] in self?.changeCurrentTime() }
            engine.onStopped = { [weak self] in self?.nowPlayingCenter.nowPlayingInfo = nil }
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

    func onChatOpen(title: String) {
        self.title = title
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
            // the recorded message itself, which matters far more than any on-device side effect of
            // interrupting it instead (including VoiceOver's own interruption earcon - tried several
            // ways to avoid that without reintroducing the bleed risk; none of them held up, so this
            // is deliberately the plain, unconditional version).
            let options: AVAudioSession.CategoryOptions = [
                .allowAirPlay,
                .allowBluetoothHFP,
                .allowBluetoothA2DP,
                .defaultToSpeaker,
                .overrideMutedMicrophoneInterruption,
            ]
            try audioSession.setCategory(.playAndRecord, mode: .default, policy: .default, options: options)
            // Documented to suppress system sounds/haptics - including VoiceOver's own earcons -
            // for the duration of the recording; `false` is already AVAudioSession's default, but
            // setting it explicitly (rather than relying on the implicit default) is untested here
            // and worth trying against the live "Screen refreshed" earcon on recording start.
            try audioSession.setAllowHapticsAndSystemSoundsDuringRecording(false)
            try audioSession.setActive(true)
        } catch {
            log("Error setting audioSessionRecord: \(error)")
        }
    }

    /// Deactivates the session right when a recording ends, instead of leaving it active in
    /// `.playAndRecord` until the *next* recording starts. Without this, that next
    /// `setAudioSessionRecord()` has to tear down a still-live session first, which is exactly the
    /// kind of deactivation that interrupts VoiceOver's own audio and makes it play its
    /// context-change earcon on resume - so only the first recording in a session was ever silent.
    func endAudioSessionRecord() {
        do {
            try audioSession.setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            log("Error ending audioSessionRecord: \(error)")
        }
    }

    // MARK: Private

    @ObservationIgnored private var title = ""
    @ObservationIgnored private let engine: VoiceMessagePlaybackEngine
    private let audioSession = AVAudioSession.sharedInstance()
    private let nowPlayingCenter = MPNowPlayingInfoCenter.default()
    private let commandCenter = MPRemoteCommandCenter.shared()

    private func changeCurrentTime() {
        nowPlayingCenter.nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] = Double(currentTime)
    }

    private func setAudioSessionPlayback() -> Bool {
        do {
            try audioSession.setCategory(.playback, mode: .spokenAudio, policy: .default, options: [
                .mixWithOthers,
                .interruptSpokenAudioAndMixWithOthers,
            ])
            try audioSession.setActive(true, options: [])
            let outputs = audioSession.currentRoute
                .outputs
                .map { "\($0.portType.rawValue):\($0.portName)" }
                .joined(separator: ",")
            voicePlaybackTrace("session active outputs=[\(outputs)] volume=\(audioSession.outputVolume)")
            return true
        } catch {
            voicePlaybackTrace("session failed: \(error.localizedDescription)")
            log("Error setting audioSessionPlayback: \(error)")
            return false
        }
    }

    private func setCommandCenterControls() {
        commandCenter.skipBackwardCommand.preferredIntervals = [5.0]
        commandCenter.skipForwardCommand.preferredIntervals = [5.0]

        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            return MainActor.assumeIsolated {
                guard !self.savedMediaPath.isEmpty, self.engine.isReady, !self.isPlaying else { return .commandFailed }
                self.engine.play()
                return .success
            }
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            return MainActor.assumeIsolated {
                guard !self.savedMediaPath.isEmpty, self.engine.isReady, self.isPlaying else { return .commandFailed }
                self.engine.pause()
                return .success
            }
        }

        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            return MainActor.assumeIsolated {
                guard !self.savedMediaPath.isEmpty, self.engine.isReady else { return .commandFailed }
                if self.isPlaying {
                    self.engine.pause()
                } else {
                    self.engine.play()
                }
                return .success
            }
        }

        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            nonisolated(unsafe) let event = event
            return MainActor.assumeIsolated {
                guard let self, let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                    return .commandFailed
                }
                self.engine.seek(to: positionEvent.positionTime)
                return .success
            }
        }

        commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            return MainActor.assumeIsolated {
                guard !self.savedMediaPath.isEmpty, self.engine.isReady else { return .commandFailed }
                self.engine.seekForward()
                return .success
            }
        }

        commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            return MainActor.assumeIsolated {
                guard !self.savedMediaPath.isEmpty, self.engine.isReady else { return .commandFailed }
                self.engine.seekBackward()
                return .success
            }
        }
    }

    private func setNowPlaying() {
        var info = [String: Any]()
        info[MPMediaItemPropertyTitle] = title
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = Double(currentTime)
        info[MPMediaItemPropertyPlaybackDuration] = Double(MainActor.assumeIsolated { engine.duration })
        nowPlayingCenter.nowPlayingInfo = info
    }
}
