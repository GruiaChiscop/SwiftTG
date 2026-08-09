// NotificationService.swift

import os
import UserNotifications

private let logger = Logger(subsystem: "com.gruiachiscop.BetterTG", category: "NotificationService")

// MARK: - NotificationService

/// Mutates an incoming Telegram push (which arrives with `mutable-content: 1`, same as the
/// official app) to play the custom sound configured for its chat or scope, if any. Has no TDLib
/// access of its own - a second process can't open the same locked TDLib database the main app
/// already has open - so it only reads the small manifest + cached sound files the main app
/// already prepared in the shared App Group container (see `TelegramNotificationSoundCache.swift`
/// and `TelegramNotificationSoundManifest.swift`).
final class NotificationService: UNNotificationServiceExtension {
    // MARK: Internal

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void,
    ) {
        self.contentHandler = contentHandler
        let bestAttemptContent = request.content.mutableCopy() as? UNMutableNotificationContent
        self.bestAttemptContent = bestAttemptContent

        // The NSE has no other maintenance run to piggyback on - sweep stale sound copies out of
        // this extension's own Library/Sounds (see `localSoundFileName(copyingFrom:)`) here, before
        // adding today's, so switching sounds doesn't leave old ones behind forever.
        TelegramNotificationSoundManifest.pruneOrphanedFiles()

        guard let bestAttemptContent else {
            contentHandler(request.content)
            return
        }

        // Telegram's server pre-resolves the correct sound for this specific notification
        // (factoring in whatever per-chat/per-topic/mention override applies - the client never
        // has to work that out itself) and embeds it as `aps.ringtone`, a saved-notification-sound
        // id - confirmed against a real push payload and against TDLib's own decoder
        // (`NotificationManager.cpp`'s `ringtone_id` handling). If we've already cached that exact
        // sound (keyed by id, the same way `TelegramNotificationSoundCache` always has), this is
        // strictly more correct than the chat/scope-keyed fallback below, since it's the only path
        // that can ever reflect a per-topic override.
        if let ringtoneId = Self.ringtoneId(from: request.content.userInfo) {
            if ringtoneId == 0 {
                bestAttemptContent.sound = nil
                contentHandler(bestAttemptContent)
                return
            }
            let fileName = TelegramNotificationSoundManifest.fileName(for: ringtoneId)
            if let cachedURL = TelegramNotificationSoundManifest.soundFileURL(named: fileName),
               FileManager.default.fileExists(atPath: cachedURL.path),
               let localFileName = TelegramNotificationSoundManifest.localSoundFileName(copyingFrom: cachedURL)
            {
                bestAttemptContent.sound = UNNotificationSound(named: UNNotificationSoundName(localFileName))
                contentHandler(bestAttemptContent)
                return
            }
        }

        // Fallback: the sound the server pointed at (if any) isn't cached locally yet - e.g. the
        // user just switched to a sound never played on this device before. Approximate with
        // whatever this chat/scope was last known to use.
        let chatKey = Self.chatKey(from: request.content.userInfo)
        let scopeKey = Self.scopeKey(from: request.content.userInfo)
        let resolvedKey = [chatKey, scopeKey]
            .compactMap(\.self)
            .first { TelegramNotificationSoundManifest.soundFileURL(forScopeKey: $0) != nil }

        if let resolvedKey, let soundURL = TelegramNotificationSoundManifest.soundFileURL(forScopeKey: resolvedKey) {
            // UNNotificationSound(named:) only resolves a bare filename against this process's own
            // container, not the shared App Group container the cache actually lives in.
            if let localFileName = TelegramNotificationSoundManifest.localSoundFileName(copyingFrom: soundURL) {
                bestAttemptContent.sound = UNNotificationSound(named: UNNotificationSoundName(localFileName))
            } else {
                logger
                    .error(
                        "didReceive: local sound copy failed for \(resolvedKey, privacy: .public), falling back to .default",
                    )
                bestAttemptContent.sound = .default
            }
        }

        contentHandler(bestAttemptContent)
    }

    override func serviceExtensionTimeWillExpire() {
        logger.error("serviceExtensionTimeWillExpire")
        if let contentHandler, let bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }

    // MARK: Private

    private var bestAttemptContent: UNMutableNotificationContent?
    private var contentHandler: ((UNNotificationContent) -> Void)?

    /// Reads the server-pre-resolved sound id, if any - `0` means TDLib's own convention for
    /// "explicitly silent" (mirrors `NotificationManager.cpp` setting `ringtone_id = 0` when the
    /// payload's `silent` field is present), distinct from `nil` ("no server hint, use the
    /// chat/scope-keyed fallback").
    private static func ringtoneId(from userInfo: [AnyHashable: Any]) -> Int64? {
        let aps = userInfo["aps"] as? [AnyHashable: Any]
        if (userInfo["silent"] ?? aps?["silent"]) != nil {
            return 0
        }
        guard let raw = userInfo["ringtone"] ?? aps?["ringtone"] else { return nil }
        if let number = raw as? NSNumber {
            return number.int64Value
        }
        if let string = raw as? String {
            return Int64(string)
        }
        return nil
    }

    /// Mirrors the payload key names `TelegramNotificationPayload` (main app target) already
    /// parses real Telegram push payloads for - duplicated here rather than shared cross-target,
    /// since that file lives in the main app's own folder rather than the shared one.
    private static func scopeKey(from userInfo: [AnyHashable: Any]) -> String? {
        let aps = userInfo["aps"] as? [AnyHashable: Any]
        func has(_ keys: [String]) -> Bool {
            keys.contains { (userInfo[$0] ?? aps?[$0]) != nil }
        }
        if has(["channel_id", "channelId"]) {
            return "channel"
        }
        if has(["basic_group_id", "basicGroupId", "supergroup_id", "supergroupId"]) {
            return "group"
        }
        if has(["from_id", "fromId", "user_id", "userId", "chat_id", "chatId", "chatID"]) {
            return "private"
        }
        return nil
    }

    /// Reconstructs TDLib's own chat id encoding from the same raw payload fields
    /// `scopeKey(from:)` reads, to match how the main app keys a per-chat override (see
    /// `TelegramNotificationSoundManifest.chatKey(for:)`). Verified against a real private-chat
    /// push; the group/channel offset math follows TDLib's documented, stable id scheme but
    /// hasn't been exercised against a real group/channel push yet.
    private static func chatKey(from userInfo: [AnyHashable: Any]) -> String? {
        let aps = userInfo["aps"] as? [AnyHashable: Any]
        func firstInt64(_ keys: [String]) -> Int64? {
            for key in keys {
                guard let raw = userInfo[key] ?? aps?[key] else { continue }
                if let number = raw as? NSNumber {
                    return number.int64Value
                }
                if let string = raw as? String, let value = Int64(string) {
                    return value
                }
            }
            return nil
        }

        if let channelId = firstInt64(["channel_id", "channelId"]) {
            return TelegramNotificationSoundManifest.chatKey(for: -1_000_000_000_000 - channelId)
        }
        if let supergroupId = firstInt64(["supergroup_id", "supergroupId"]) {
            return TelegramNotificationSoundManifest.chatKey(for: -1_000_000_000_000 - supergroupId)
        }
        if let basicGroupId = firstInt64(["basic_group_id", "basicGroupId"]) {
            return TelegramNotificationSoundManifest.chatKey(for: -basicGroupId)
        }
        if let userId = firstInt64(["from_id", "fromId", "user_id", "userId"]) {
            return TelegramNotificationSoundManifest.chatKey(for: userId)
        }
        if let chatId = firstInt64(["chat_id", "chatId", "chatID"]) {
            return TelegramNotificationSoundManifest.chatKey(for: chatId)
        }
        return nil
    }
}
