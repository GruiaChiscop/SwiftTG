// TelegramRecordingPlaybackSettings.swift

import Foundation

// MARK: - TelegramPauseMusicSetting

enum TelegramPauseMusicSetting {
    static let defaultsKey = "BetterTG.recording.pauseMusicWhileRecording"

    /// Defaults to `true` - matches the app's existing hardcoded behavior (see
    /// `Media.setAudioSessionRecord()`'s comment) for anyone who hasn't visited the setting yet.
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: defaultsKey) == nil
            ? true
            : UserDefaults.standard.bool(forKey: defaultsKey)
    }
}

// MARK: - TelegramRaiseToListenSetting

enum TelegramRaiseToListenSetting {
    static let defaultsKey = "BetterTG.playback.raiseToListen"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: defaultsKey)
    }
}
