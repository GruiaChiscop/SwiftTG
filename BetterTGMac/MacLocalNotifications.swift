// MacLocalNotifications.swift

import Foundation
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
        playsSound: Bool,
    ) async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = playsSound ? .default : nil
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
}
