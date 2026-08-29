// TelegramDeliveredNotifications.swift

import TDLibKit
import UserNotifications

/// Clears system notifications for a chat once it's opened, so Notification Center matches what's
/// actually still unread - iOS only removes the one notification the user tapped, not its siblings.
enum TelegramDeliveredNotifications {
    // MARK: Internal

    static func clear(for chat: Chat) {
        let center = UNUserNotificationCenter.current()
        center.getDeliveredNotifications { notifications in
            let identifiers = notifications
                .filter { belongs($0.request.content.userInfo, to: chat) }
                .map(\.request.identifier)
            guard !identifiers.isEmpty else { return }
            center.removeDeliveredNotifications(withIdentifiers: identifiers)
        }
    }

    // MARK: Private

    private static func belongs(_ userInfo: [AnyHashable: Any], to chat: Chat) -> Bool {
        guard let target = TelegramNotificationPayload.target(from: userInfo) else { return false }
        if target.chatIds.contains(chat.id) {
            return true
        }
        // A private chat's TDLib id is the peer's user id, so a payload carrying only `from_id`
        // still resolves here.
        let peerUserId: Int64? =
            switch chat.type {
            case .chatTypePrivate(let value): value.userId
            case .chatTypeSecret(let value): value.userId
            default: nil
            }
        if let peerUserId, target.userIds.contains(peerUserId) || target.chatIds.contains(peerUserId) {
            return true
        }
        switch chat.type {
        case .chatTypeSupergroup(let value):
            return target.supergroupIds.contains(value.supergroupId)
        case .chatTypeBasicGroup(let value):
            return target.basicGroupIds.contains(value.basicGroupId)
        case .chatTypePrivate, .chatTypeSecret:
            return false
        }
    }
}
