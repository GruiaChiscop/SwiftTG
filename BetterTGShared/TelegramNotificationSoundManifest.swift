// TelegramNotificationSoundManifest.swift

import Foundation

// MARK: - TelegramNotificationSoundManifest

/// Foundation-only half of the notification sound cache, deliberately free of any TDLib
/// dependency so the Notification Service Extension (which has no TDLib access of its own - a
/// second process can't open the same locked TDLib database) can read it directly. See
/// `TelegramNotificationSoundCache.swift` for the TDLib-backed half that actually downloads and
/// transcodes sounds; this file only knows how to read/write the resulting manifest and resolve
/// where things live in the shared App Group container.
enum TelegramNotificationSoundManifest {
    // MARK: Internal

    /// Scope key ("private"/"group"/"channel") -> the sound id currently configured for it.
    typealias Contents = [String: Int64]

    static var soundsDirectoryURL: URL? {
        TelegramShareExtension.appGroupContainerURL?.appending(path: soundsDirectoryName, directoryHint: .isDirectory)
    }

    /// The `-v3` bumps past files cached by earlier (broken) transcoder versions: v1 wrote
    /// unconverted source-format samples into a file declared as Int16 PCM; v2's AVAudioConverter
    /// step failed outright (Core Audio error -50) but still left an empty destination file behind.
    static func fileName(for soundId: Int64) -> String {
        "sound-\(soundId)-v3.caf"
    }

    static func soundFileURL(named fileName: String) -> URL? {
        soundsDirectoryURL?.appending(path: fileName, directoryHint: .notDirectory)
    }

    /// Resolves the cached, still-present sound file registered for a scope key, if any.
    static func soundFileURL(forScopeKey scopeKey: String) -> URL? {
        guard
            let soundId = load()[scopeKey], soundId > 0,
            let url = soundFileURL(named: fileName(for: soundId)),
            FileManager.default.fileExists(atPath: url.path)
        else { return nil }
        return url
    }

    static func load() -> Contents {
        guard let url = manifestURL, let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode(Contents.self, from: data)) ?? [:]
    }

    static func save(_ contents: Contents) {
        guard let url = manifestURL, let data = try? JSONEncoder().encode(contents) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Deletes any file in the shared cache no longer referenced by any scope in the manifest -
    /// call after every manifest change (and once at launch) so switching sounds doesn't leave
    /// orphaned files behind forever. Also sweeps up files left by older, now-unused filename
    /// versions (see the `-v3` comment on `fileName(for:)`), since those never match a current
    /// entry either.
    static func pruneOrphanedFiles() {
        guard let soundsDirectoryURL else { return }
        let referencedFileNames = Set(load().values.map(fileName(for:)))
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: soundsDirectoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles],
        ) else { return }

        for url in entries where !referencedFileNames.contains(url.lastPathComponent) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// `UNNotificationSound(named:)` only resolves a bare filename against the *calling process's
    /// own* container - not the shared App Group container the file actually lives in, even though
    /// that process can read it there just fine. So whichever process is about to hand a sound off
    /// to UserNotifications (the Notification Service Extension, or `MacLocalNotifications` on
    /// macOS) must first copy it into its own `Library/Sounds`. Cheap and idempotent - skips the
    /// copy if already there.
    @discardableResult
    static func localSoundFileName(copyingFrom sourceURL: URL) -> String? {
        guard let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            return nil
        }
        let localSoundsDir = libraryURL.appending(path: "Sounds", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: localSoundsDir, withIntermediateDirectories: true)
        let destinationURL = localSoundsDir.appending(path: sourceURL.lastPathComponent, directoryHint: .notDirectory)

        if !FileManager.default.fileExists(atPath: destinationURL.path) {
            try? FileManager.default.removeItem(at: destinationURL)
            try? FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        }
        return FileManager.default.fileExists(atPath: destinationURL.path) ? destinationURL.lastPathComponent : nil
    }

    // MARK: Private

    private static let manifestName = "NotificationSoundManifest.json"
    private static let soundsDirectoryName = "Library/Sounds"

    private static var manifestURL: URL? {
        TelegramShareExtension.appGroupContainerURL?.appending(path: manifestName, directoryHint: .notDirectory)
    }
}
