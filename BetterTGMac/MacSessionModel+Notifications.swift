// MacSessionModel+Notifications.swift

import AppKit
@preconcurrency import TDLibKit

extension MacSessionModel {
    // MARK: Internal (called from `observeSession()` in the core file)

    func handleNotificationUpdate(_ update: Update) {
        guard case .updateNotificationGroup(let group) = update else { return }

        notifications.remove(
            notificationGroupId: group.notificationGroupId,
            notificationIds: group.removedNotificationIds,
        )

        guard openedChatId != group.chatId || !NSApplication.shared.isActive else { return }
        let title = chatList.items[group.chatId]?.displayTitle ?? "SwiftTG"
        for notification in group.addedNotifications {
            guard Date().timeIntervalSince1970 - TimeInterval(notification.date) < 3600,
                  let body = notificationBody(notification)
            else { continue }
            let soundId = notification.isSilent ? 0 : group.notificationSoundId
            Task {
                await notifications.deliver(
                    chatId: group.chatId,
                    title: title,
                    body: body,
                    notificationGroupId: group.notificationGroupId,
                    notificationId: notification.id,
                    soundId: soundId,
                    service: service,
                )
            }
        }
    }

    // MARK: Private

    private func notificationBody(_ notification: TDLibKit.Notification) -> String? {
        switch notification.type {
        case .notificationTypeNewMessage(let value):
            guard !value.message.isOutgoing else { return nil }
            return value.showPreview ? macMessageText(value.message) : "You have a new message."
        case .notificationTypeNewPushMessage(let value):
            guard !value.isOutgoing else { return nil }
            return value.senderName.isEmpty ? "You have a new message." : "New message from \(value.senderName)."
        case .notificationTypeNewCall, .notificationTypeNewSecretChat:
            return nil
        }
    }
}
