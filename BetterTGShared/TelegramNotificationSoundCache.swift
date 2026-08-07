// TelegramNotificationSoundCache.swift

import AVFoundation
import Foundation
import os
@preconcurrency import TDLibKit

private let soundCacheLogger = Logger(subsystem: "com.gruiachiscop.BetterTG", category: "NotificationSoundCache")

private func debug(_ message: String) {
    soundCacheLogger.info("\(message, privacy: .public)")
}

// MARK: - TelegramNotificationSoundCache

/// Downloads and caches custom notification sounds, converted to a format `UNNotificationSound`
/// accepts. Builds on `TelegramNotificationSoundManifest`'s plain file/manifest I/O by adding the
/// TDLib-backed download+transcode step - kept in a separate file so the Notification Service
/// Extension (no TDLib access of its own) can link the manifest half without pulling in TDLibKit.
/// macOS reads/writes the same cache directly too (no extension needed there -
/// `MacLocalNotifications` builds its own local notifications and can just resolve the file
/// itself), so a sound is downloaded once and shared however it's referenced.
enum TelegramNotificationSoundCache {
    // MARK: Internal

    static func key(for scope: NotificationSettingsScope) -> String {
        switch scope {
        case .notificationSettingsScopePrivateChats: "private"
        case .notificationSettingsScopeGroupChats: "group"
        case .notificationSettingsScopeChannelChats: "channel"
        }
    }

    /// The `Library/Sounds` filename registered for `scope`, if any - `nil` means "no custom
    /// sound cached", which callers should treat as the system default tone.
    static func soundFileName(for scope: NotificationSettingsScope) -> String? {
        TelegramNotificationSoundManifest.soundFileURL(forScopeKey: key(for: scope))?.lastPathComponent
    }

    /// Downloads, transcodes, and caches `soundId` if it isn't already - safe to call repeatedly.
    /// `soundId <= 0` (default/off) has no file to cache and returns `nil`.
    @discardableResult
    static func ensureCached(soundId: TdInt64, service: any TelegramService) async -> URL? {
        guard soundId.rawValue > 0 else { return nil }
        let fileName = TelegramNotificationSoundManifest.fileName(for: soundId.rawValue)
        if let existingURL = TelegramNotificationSoundManifest.soundFileURL(named: fileName),
           FileManager.default.fileExists(atPath: existingURL.path)
        {
            debug("ensureCached: \(fileName) already cached at \(existingURL.path)")
            return existingURL
        }

        guard let sound = try? await service.getSavedNotificationSound(notificationSoundId: soundId) else {
            debug("ensureCached: getSavedNotificationSound FAILED for id \(soundId.rawValue)")
            return nil
        }
        guard let downloadedFile = try? await service.downloadFile(
            fileId: sound.sound.id,
            limit: 0,
            offset: 0,
            priority: 1,
            synchronous: true,
        ), downloadedFile.local.isDownloadingCompleted, !downloadedFile.local.path.isEmpty else {
            debug("ensureCached: downloadFile FAILED for fileId \(sound.sound.id)")
            return nil
        }

        debug("ensureCached: downloaded to \(downloadedFile.local.path), transcoding to \(fileName)")
        let result = transcodeToCAF(sourcePath: downloadedFile.local.path, destinationFileName: fileName)
        if result == nil {
            debug("ensureCached: transcodeToCAF FAILED for \(fileName)")
        }
        return result
    }

    /// Updates `scope`'s manifest entry to `soundId` and makes sure the underlying file (if any)
    /// is cached. Call whenever a scope's chosen sound changes, and once at launch to resync.
    static func refresh(scope: NotificationSettingsScope, soundId: TdInt64, service: any TelegramService) async {
        var manifest = TelegramNotificationSoundManifest.load()
        let scopeKey = key(for: scope)

        guard soundId.rawValue > 0 else {
            manifest[scopeKey] = nil
            TelegramNotificationSoundManifest.save(manifest)
            TelegramNotificationSoundManifest.pruneOrphanedFiles()
            debug("refresh: cleared scope \(scopeKey)")
            return
        }

        let cachedURL = await ensureCached(soundId: soundId, service: service)
        manifest[scopeKey] = soundId.rawValue
        TelegramNotificationSoundManifest.save(manifest)
        TelegramNotificationSoundManifest.pruneOrphanedFiles()
        debug(
            "refresh: scope \(scopeKey) -> soundId \(soundId.rawValue), cached=\(cachedURL != nil), soundsDir=\(String(describing: TelegramNotificationSoundManifest.soundsDirectoryURL))",
        )
    }

    // MARK: Private

    /// `UNNotificationSound(named:)` requires Linear PCM/IMA4/µLaw/aLaw wrapped in a caf/aif/wav
    /// container - Telegram's saved sounds are plain MP3, so they need converting even though
    /// `AVAudioFile` can already decode them for local preview playback.
    ///
    /// No manual sample-format conversion here (an earlier version hand-rolled one via
    /// `AVAudioConverter` and kept hitting opaque Core Audio errors): `AVAudioFile` already decodes
    /// MP3 on read into its own `processingFormat` (Linear PCM, just usually 32-bit float rather
    /// than integer) - CAF natively supports float Linear PCM, so writing a file declared with that
    /// *same* format needs no conversion step at all, just a plain read/write copy.
    private static func transcodeToCAF(sourcePath: String, destinationFileName: String) -> URL? {
        guard let soundsDirectoryURL = TelegramNotificationSoundManifest.soundsDirectoryURL else {
            debug("transcodeToCAF: no App Group container URL (soundsDirectoryURL is nil)")
            return nil
        }
        do {
            try FileManager.default.createDirectory(at: soundsDirectoryURL, withIntermediateDirectories: true)
        } catch {
            debug("transcodeToCAF: createDirectory FAILED: \(error.localizedDescription)")
        }
        let destinationURL = soundsDirectoryURL.appending(path: destinationFileName, directoryHint: .notDirectory)
        try? FileManager.default.removeItem(at: destinationURL)

        guard let sourceFile = try? AVAudioFile(forReading: URL(fileURLWithPath: sourcePath)) else {
            debug("transcodeToCAF: couldn't open source file at \(sourcePath)")
            return nil
        }
        let format = sourceFile.processingFormat
        debug("transcodeToCAF: source processingFormat = \(format), length=\(sourceFile.length) frames")

        guard let destinationFile = try? AVAudioFile(
            forWriting: destinationURL,
            settings: format.settings,
            commonFormat: format.commonFormat,
            interleaved: format.isInterleaved,
        ) else {
            debug("transcodeToCAF: couldn't create destination file at \(destinationURL.path)")
            return nil
        }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096) else {
            debug("transcodeToCAF: couldn't allocate PCM buffer")
            return nil
        }

        do {
            var totalFrames: AVAudioFramePosition = 0
            while true {
                try sourceFile.read(into: buffer)
                if buffer.frameLength == 0 { break }
                try destinationFile.write(from: buffer)
                totalFrames += AVAudioFramePosition(buffer.frameLength)
            }
            debug("transcodeToCAF: wrote \(destinationURL.path), frames=\(totalFrames)")
        } catch {
            debug("transcodeToCAF: read/write FAILED: \(error.localizedDescription)")
            return nil
        }
        return destinationURL
    }
}

// MARK: - TelegramNotificationSoundCacheRefresh

/// Re-syncs every scope's cached sound file - call once at launch, since the manifest can drift
/// from TDLib's actual settings (e.g. after a fresh install, or a sound chosen on another device).
enum TelegramNotificationSoundCacheRefresh {
    static func refreshAll(service: any TelegramService) async {
        for item in telegramNotificationScopeItems {
            guard let settings = try? await service.getScopeNotificationSettings(scope: item.scope) else { continue }
            await TelegramNotificationSoundCache.refresh(scope: item.scope, soundId: settings.soundId, service: service)
        }
    }
}
