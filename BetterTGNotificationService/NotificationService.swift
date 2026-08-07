// NotificationService.swift

import os
import UserNotifications

private let logger = Logger(subsystem: "com.gruiachiscop.BetterTG", category: "NotificationService")

// MARK: - NotificationService

/// Mutates an incoming Telegram push (which arrives with `mutable-content: 1`, same as the
/// official app) to play the custom sound configured for its scope, if any. Has no TDLib access
/// of its own - a second process can't open the same locked TDLib database the main app already
/// has open - so it only reads the small manifest + cached sound files the main app already
/// prepared in the shared App Group container (see `TelegramNotificationSoundCache.swift` and
/// `TelegramNotificationSoundManifest.swift`).
final class NotificationService: UNNotificationServiceExtension {
    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void,
    ) {
        self.contentHandler = contentHandler
        let bestAttemptContent = request.content.mutableCopy() as? UNMutableNotificationContent
        self.bestAttemptContent = bestAttemptContent

        guard let bestAttemptContent else {
            contentHandler(request.content)
            return
        }

        let scopeKey = Self.scopeKey(from: request.content.userInfo)
        if let scopeKey, let soundURL = TelegramNotificationSoundManifest.soundFileURL(forScopeKey: scopeKey) {
            // UNNotificationSound(named:) only resolves a bare filename against this process's own
            // container, not the shared App Group container the cache actually lives in.
            if let localFileName = TelegramNotificationSoundManifest.localSoundFileName(copyingFrom: soundURL) {
                bestAttemptContent.sound = UNNotificationSound(named: UNNotificationSoundName(localFileName))
            } else {
                logger.error("didReceive: local sound copy failed for scope \(scopeKey, privacy: .public), falling back to .default")
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

    /// Mirrors the payload key names `TelegramNotificationPayload` (main app target) already
    /// parses real Telegram push payloads for - duplicated here rather than shared cross-target,
    /// since that file lives in the main app's own folder rather than the shared one.
    private static func scopeKey(from userInfo: [AnyHashable: Any]) -> String? {
        let aps = userInfo["aps"] as? [AnyHashable: Any]
        func has(_ keys: [String]) -> Bool {
            keys.contains { (userInfo[$0] ?? aps?[$0]) != nil }
        }
        if has(["channel_id", "channelId"]) { return "channel" }
        if has(["basic_group_id", "basicGroupId", "supergroup_id", "supergroupId"]) { return "group" }
        if has(["from_id", "fromId", "user_id", "userId", "chat_id", "chatId", "chatID"]) { return "private" }
        return nil
    }
}
