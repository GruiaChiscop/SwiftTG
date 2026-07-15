// MacLocalNotifications.swift

import Foundation
@preconcurrency import UserNotifications

final class MacLocalNotifications: @unchecked Sendable {
    // MARK: Internal

    func requestAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
    }

    func deliver(chatId: Int64, title: String, body: String) async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["chatId": String(chatId)]
        try? await center.add(UNNotificationRequest(
            identifier: "message-\(chatId)-\(UUID().uuidString)",
            content: content,
            trigger: nil,
        ))
    }

    // MARK: Private

    private let center = UNUserNotificationCenter.current()
}
