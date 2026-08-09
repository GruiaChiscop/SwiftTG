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
            let defaultSoundId: TdInt64 = notification.isSilent ? 0 : group.notificationSoundId
            let chatId = group.chatId
            let notificationGroupId = group.notificationGroupId
            Task {
                let soundId = await resolvedSoundId(for: notification, chatId: chatId, defaultSoundId: defaultSoundId)
                await notifications.deliver(
                    chatId: chatId,
                    title: title,
                    body: body,
                    notificationGroupId: notificationGroupId,
                    notificationId: notification.id,
                    soundId: soundId,
                    service: service,
                )
            }
        }
    }

    // MARK: Private

    /// `group.notificationSoundId` is TDLib's chat-level resolution - `updateNotificationGroup`
    /// carries no topic-level field, so a forum topic's own sound/mute override (set via
    /// `setForumTopicNotificationSettings`, stored on `ForumTopic.notificationSettings`) isn't
    /// reflected in it. Checked here instead, since this runs in-process with live TDLib access -
    /// unlike iOS's Notification Service Extension, which can't do the same: the raw push payload
    /// it has to work from carries no topic information at all (confirmed against TDLib's own
    /// push-payload decoder), so this override can only ever be honored on macOS.
    private func resolvedSoundId(
        for notification: TDLibKit.Notification,
        chatId: Int64,
        defaultSoundId: TdInt64,
    ) async -> TdInt64 {
        guard !notification.isSilent,
              case .notificationTypeNewMessage(let value) = notification.type,
              case .messageTopicForum(let forum) = value.message.topicId,
              let topic = try? await service.getForumTopic(chatId: chatId, forumTopicId: forum.forumTopicId)
        else { return defaultSoundId }

        let settings = topic.notificationSettings
        if !settings.useDefaultMuteFor, settings.muteFor > 0 {
            return 0
        }
        guard !settings.useDefaultSound else { return defaultSoundId }
        return settings.soundId
    }

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
