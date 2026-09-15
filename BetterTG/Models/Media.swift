// Media.swift

import AVFoundation
import Observation
import UIKit

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
            engine.playbackRate = TelegramVoicePlaybackRateSettings.rate
            engine.onWillPlay = { [weak self] in self?.setAudioSessionPlayback() ?? false }
            engine.onPlayStarted = { [weak self] in self?.startRaiseToListenMonitoring() }
            engine.onStopped = { [weak self] in self?.stopRaiseToListenMonitoring() }
        }
    }

    // MARK: Internal

    static let shared = Media()

    var savedMediaPath: String { MainActor.assumeIsolated { engine.currentPath } ?? "" }
    var isPlaying: Bool { MainActor.assumeIsolated { engine.isPlaying } }
    var currentTime: Int32 { Int32(MainActor.assumeIsolated { engine.currentTime }) }
    var playbackRate: Float { MainActor.assumeIsolated { engine.playbackRate } }

    /// Cycles through `TelegramVoicePlaybackRateSettings.presets` and persists the choice for
    /// every voice note played afterward. Returns the new rate so callers can announce it.
    @discardableResult
    func cyclePlaybackRate() -> Float {
        let newRate = TelegramVoicePlaybackRateSettings.next(after: playbackRate)
        MainActor.assumeIsolated { engine.playbackRate = newRate }
        TelegramVoicePlaybackRateSettings.rate = newRate
        return newRate
    }

    func stop() {
        MainActor.assumeIsolated { engine.stop() }
    }

    func onChatDismiss() {
        MainActor.assumeIsolated {
            engine.pause()
            // `pause()` (unlike `stop()`) doesn't fire `onStopped`, so leaving the chat mid-
            // playback would otherwise leave proximity monitoring running indefinitely.
            stopRaiseToListenMonitoring()
        }
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
    @ObservationIgnored private var proximityObserver: NSObjectProtocol?

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

    /// "Raise to Listen": while a voice message plays through the speaker, bringing the phone to
    /// your ear switches to the earpiece, same as a call - it never starts playback on its own,
    /// only re-routes audio that's already playing (see the user's own explanation of what they
    /// want, distinct from Telegram-iOS's more aggressive "raise picks a message to play" version).
    private func startRaiseToListenMonitoring() {
        guard TelegramRaiseToListenSetting.isEnabled, proximityObserver == nil else { return }
        UIDevice.current.isProximityMonitoringEnabled = true
        proximityObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.proximityStateDidChangeNotification,
            object: nil,
            queue: .main,
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.proximityStateDidChange() }
        }
    }

    private func stopRaiseToListenMonitoring() {
        if let proximityObserver {
            NotificationCenter.default.removeObserver(proximityObserver)
        }
        proximityObserver = nil
        UIDevice.current.isProximityMonitoringEnabled = false
        // Whatever plays next shouldn't come out of the earpiece just because the last thing did.
        _ = setAudioSessionPlayback()
    }

    @MainActor
    private func proximityStateDidChange() {
        guard engine.isPlaying else { return }
        if UIDevice.current.proximityState {
            setAudioSessionEarpiece()
        } else {
            _ = setAudioSessionPlayback()
        }
    }

    private func setAudioSessionEarpiece() {
        // Headphones/Bluetooth output already routes away from the earpiece regardless of
        // category - leave a route the user chose deliberately alone.
        let hasExternalOutput = audioSession.currentRoute.outputs.contains {
            $0.portType != .builtInSpeaker && $0.portType != .builtInReceiver
        }
        guard !hasExternalOutput else { return }
        do {
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [])
            try audioSession.setActive(true)
        } catch {
            log("Error setting audioSessionEarpiece: \(error)")
        }
    }
}
