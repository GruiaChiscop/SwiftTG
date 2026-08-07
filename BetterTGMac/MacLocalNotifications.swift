// MacLocalNotifications.swift

import Foundation
@preconcurrency import TDLibKit
@preconcurrency import UserNotifications

final class MacLocalNotifications: @unchecked Sendable {
    // MARK: Internal

    func requestAuthorization() async -> Bool {
        await (try? center.requestAuthorization(options: [.alert, .badge, .sound])) == true
    }

    func deliver(
        chatId: Int64,
        title: String,
        body: String,
        notificationGroupId: Int,
        notificationId: Int,
        soundId: TdInt64,
        service: any TelegramService,
    ) async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = await resolvedSound(soundId: soundId, service: service)
        content.threadIdentifier = String(chatId)
        content.userInfo = ["chatId": String(chatId)]
        try? await center.add(UNNotificationRequest(
            identifier: Self.identifier(groupId: notificationGroupId, notificationId: notificationId),
            content: content,
            trigger: nil,
        ))
    }

    func remove(notificationGroupId: Int, notificationIds: [Int]) {
        let identifiers = notificationIds.map {
            Self.identifier(groupId: notificationGroupId, notificationId: $0)
        }
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    // MARK: Private

    private let center = UNUserNotificationCenter.current()

    private static func identifier(groupId: Int, notificationId: Int) -> String {
        "tdlib-\(groupId)-\(notificationId)"
    }

    /// `soundId` follows TDLib's own convention: 0 is silent, negative means "use the app-default
    /// sound", positive references one of the account's saved cloud sounds.
    private func resolvedSound(soundId: TdInt64, service: any TelegramService) async -> UNNotificationSound? {
        guard soundId != 0 else { return nil }
        guard
            soundId > 0,
            let url = await TelegramNotificationSoundCache.ensureCached(soundId: soundId, service: service),
            // UNNotificationSound(named:) only resolves a bare filename against this process's own
            // container, not the shared App Group container the cache actually lives in.
            let localFileName = TelegramNotificationSoundManifest.localSoundFileName(copyingFrom: url)
        else { return .default }
        return UNNotificationSound(named: UNNotificationSoundName(localFileName))
    }
}
