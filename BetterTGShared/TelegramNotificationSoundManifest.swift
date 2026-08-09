// TelegramNotificationSoundManifest.swift

import Foundation

// MARK: - TelegramNotificationSoundManifest

/// Foundation-only half of the notification sound cache, deliberately free of any TDLib
/// dependency so the Notification Service Extension (which has no TDLib access of its own - a
/// second process can't open the same locked TDLib database) can read it directly. See
/// `TelegramNotificationSoundCache.swift` for the TDLib-backed half that actually downloads and
/// transcodes sounds; this file only knows how to read/write the resulting manifest and resolve
/// where things live.
///
/// On iOS this has to be the shared App Group container, since the main app and the NSE are two
/// separate processes handing files off to each other. macOS has no such extension - only
/// `MacLocalNotifications` ever reads this cache, in the same process that wrote it - so it uses
/// this app's own container instead, needing no App Group entitlement at all (and none of the
/// "would like to access data from other apps" prompt that entitlement brings with it).
enum TelegramNotificationSoundManifest {
    // MARK: Internal

    /// Scope key ("private"/"group"/"channel") or chat key ("chat:<id>") -> the sound id currently
    /// configured for it. A chat key wins over the scope it belongs to when both are present -
    /// see `soundFileURL(forScopeKey:)` callers, which try the chat key first.
    typealias Contents = [String: Int64]

    static var soundsDirectoryURL: URL? {
        storageBaseURL?.appending(path: soundsDirectoryName, directoryHint: .isDirectory)
    }

    /// TDLib's own chat id encoding, reconstructed here (not asked of TDLib - the Notification
    /// Service Extension has no TDLib access) so a chat-level override can be looked up from a raw
    /// push payload's separate `from_id`/`basic_group_id`/`channel_id` fields: private chat ids are
    /// the user id verbatim, basic groups are the negated group id, super groups/channels are
    /// offset by -1000000000000. This scheme is stable/publicly documented and used throughout
    /// TDLib, not something Telegram is expected to change.
    static func chatKey(for chatId: Int64) -> String {
        "chat:\(chatId)"
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

    /// Deletes any file in the shared cache, *and* in this calling process's own `Library/Sounds`
    /// (see `localSoundFileName(copyingFrom:)`), no longer referenced by any scope in the manifest -
    /// call after every manifest change (and once at launch) so switching sounds doesn't leave
    /// orphaned files behind forever. Also sweeps up files left by older, now-unused filename
    /// versions (see the `-v3` comment on `fileName(for:)`), since those never match a current
    /// entry either. The local half matters most for the Notification Service Extension, which
    /// has no other maintenance run than "a notification just arrived" to piggyback cleanup on.
    static func pruneOrphanedFiles() {
        let referencedFileNames = Set(load().values.map(fileName(for:)))
        pruneOrphanedFiles(in: soundsDirectoryURL, keeping: referencedFileNames)
        pruneOrphanedFiles(in: localSoundsDirectoryURL, keeping: referencedFileNames)
    }

    /// `UNNotificationSound(named:)` only resolves a bare filename against the *calling process's
    /// own* container - not the shared App Group container the file actually lives in, even though
    /// that process can read it there just fine. So whichever process is about to hand a sound off
    /// to UserNotifications (the Notification Service Extension, or `MacLocalNotifications` on
    /// macOS) must first copy it into its own `Library/Sounds`. Cheap and idempotent - skips the
    /// copy if already there.
    @discardableResult static func localSoundFileName(copyingFrom sourceURL: URL) -> String? {
        guard let localSoundsDirectoryURL else { return nil }
        try? FileManager.default.createDirectory(at: localSoundsDirectoryURL, withIntermediateDirectories: true)
        let destinationURL = localSoundsDirectoryURL
            .appending(path: sourceURL.lastPathComponent, directoryHint: .notDirectory)

        if !FileManager.default.fileExists(atPath: destinationURL.path) {
            try? FileManager.default.removeItem(at: destinationURL)
            try? FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        }
        return FileManager.default.fileExists(atPath: destinationURL.path) ? destinationURL.lastPathComponent : nil
    }

    // MARK: Private

    private static let manifestName = "NotificationSoundManifest.json"
    private static let soundsDirectoryName = "Library/Sounds"

    private static var localSoundsDirectoryURL: URL? {
        FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask)
            .first?
            .appending(path: "Sounds", directoryHint: .isDirectory)
    }

    private static var manifestURL: URL? {
        storageBaseURL?.appending(path: manifestName, directoryHint: .notDirectory)
    }

    private static var storageBaseURL: URL? {
        #if os(macOS)
        FileManager.default
.urls(for: .applicationSupportDirectory, in: .userDomainMask)
.first?
            .appending(path: "BetterTG", directoryHint: .isDirectory)
        #else
        TelegramShareExtension.appGroupContainerURL
        #endif
    }

    private static func pruneOrphanedFiles(in directoryURL: URL?, keeping referencedFileNames: Set<String>) {
        guard let directoryURL else { return }
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles],
        ) else { return }

        for url in entries where !referencedFileNames.contains(url.lastPathComponent) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
