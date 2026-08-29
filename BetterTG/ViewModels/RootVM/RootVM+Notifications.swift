// RootVM+Notifications.swift

import AudioToolbox
import Foundation
import TDLibKit
import UIKit

// MARK: - TelegramInAppNotificationBanner

/// Shown instead of a system notification banner while the app is active - see
/// `handleNotificationGroupUpdate` for why the system banner is suppressed in that state.
struct TelegramInAppNotificationBanner: Identifiable, Equatable {
    let id: String
    let chatId: Int64
    let title: String
    let body: String
    let isSilent: Bool
}

extension RootVM {
    @MainActor func openChatFromNotification(userInfo: [AnyHashable: Any]) async {
        guard let target = TelegramNotificationPayload.target(from: userInfo) else { return }

        notificationOpenGeneration &+= 1
        pendingNotificationTarget = target
        await openPendingNotificationIfReady(generation: notificationOpenGeneration)
    }

    @MainActor func resumePendingNotificationOpen() async {
        guard pendingNotificationTarget != nil else { return }
        await openPendingNotificationIfReady(generation: notificationOpenGeneration)
    }

    @MainActor func discardPendingNotificationOpen() {
        notificationOpenGeneration &+= 1
        pendingNotificationTarget = nil
    }

    /// Also used by `AppDelegate`'s notification-reply handling in `BetterTGApp.swift` to resolve
    /// which chat a "reply" action's push payload targets.
    func customChat(for target: TelegramNotificationTarget) async -> CustomChat? {
        for chatId in target.chatIds {
            if let customChat = await getCustomChat(from: chatId) {
                return customChat
            }
        }

        for userId in target.userIds {
            if let chat = try? await service.createPrivateChat(force: false, userId: userId),
               let customChat = await getCustomChat(from: chat.id)
            {
                return customChat
            }
        }

        for supergroupId in target.supergroupIds {
            if let chat = try? await service.createSupergroupChat(force: false, supergroupId: supergroupId),
               let customChat = await getCustomChat(from: chat.id)
            {
                return customChat
            }
        }

        for basicGroupId in target.basicGroupIds {
            if let customChat = await customChat(forBasicGroupId: basicGroupId) {
                return customChat
            }
        }

        for chatId in target.chatIds where chatId > 0 {
            if let customChat = await customChat(forBasicGroupId: chatId) {
                return customChat
            }
        }

        return nil
    }

    // MARK: Private

    @MainActor private func openPendingNotificationIfReady(generation: UInt64) async {
        guard generation == notificationOpenGeneration,
              let target = pendingNotificationTarget,
              let state = try? await service.getAuthorizationState(),
              case .authorizationStateReady = state,
              let customChat = await customChat(for: target),
              generation == notificationOpenGeneration,
              pendingNotificationTarget == target
        else { return }

        pendingNotificationTarget = nil
        openChatReplacingStack(customChat)
    }

    /// Telegram surfaces a notification's chat as a fresh top-level screen: any chat already
    /// pushed is replaced, so Back returns to the chat list - not to whichever chat the user
    /// happened to have open when the notification arrived. Used for both the system push tap
    /// and the in-app banner tap.
    @MainActor private func openChatReplacingStack(_ customChat: CustomChat) {
        if case .customChat(let current, _, _) = path.last, current.id == customChat.id {
            return
        }
        path = [.customChat(customChat)]
    }

    private func customChat(forBasicGroupId basicGroupId: Int64) async -> CustomChat? {
        guard let chat = try? await service.createBasicGroupChat(basicGroupId: basicGroupId, force: false)
        else { return nil }
        return await getCustomChat(from: chat.id)
    }
}

// MARK: - In-app notification banner

extension RootVM {
    // MARK: Internal

    /// Telegram-iOS's own `willPresent` never calls its completion handler for the active account
    /// (see its `AppDelegate.swift`) - the system banner never shows while the app is running, full
    /// stop, and `SharedNotificationManager` shows the app's own banner instead, driven by the same
    /// live update stream this mirrors. `AppDelegate.userNotificationCenter(_:willPresent:...)`
    /// (`BetterTGApp.swift`) does the matching suppression on our side; this is what replaces what
    /// it suppressed. Only reachable while the app is genuinely foregrounded in the first place -
    /// backgrounded/killed notifications go through the plain system push path untouched, same as
    /// before.
    @MainActor func handleNotificationGroupUpdate(_ group: UpdateNotificationGroup) {
        guard UIApplication.shared.applicationState == .active else { return }

        // A group update for the chat that's already on screen means those messages are being
        // read - clear any system notifications that were delivered for it while backgrounded.
        if currentlyOpenChatId == group.chatId {
            Task { @MainActor [weak self] in
                guard let self, let chat = await getCustomChat(from: group.chatId)?.chat else { return }
                TelegramDeliveredNotifications.clear(for: chat)
            }
            return
        }

        // TDLib re-sends `updateNotificationGroup` for every chat that still has pending
        // notifications whenever it (re)connects, so on launch a backlog spread across many chats
        // would otherwise banner and play a sound for each one. Surface only the newest notification
        // in the group, and only if it actually arrived after the app came to the foreground -
        // mirroring Telegram-iOS, which presents just `messageList.last` and suppresses anything
        // older than `delayNotificatonsUntil`.
        let baseline = notificationBannerActiveSince.timeIntervalSince1970 - Self.notificationBannerBacklogGrace
        guard let notification = group.addedNotifications
            .filter({ TimeInterval($0.date) >= baseline })
            .max(by: { $0.date < $1.date }),
            let body = Self.inAppNotificationBody(notification)
        else { return }

        let chatId = group.chatId
        let bannerId = "\(group.notificationGroupId)-\(notification.id)"
        let isSilent = notification.isSilent
        Task { @MainActor [weak self] in
            guard let self else { return }
            let title = await getCustomChat(from: chatId)?.displayTitle ?? "SwiftTG"
            guard currentlyOpenChatId != chatId else { return }
            enqueueInAppNotification(TelegramInAppNotificationBanner(
                id: bannerId,
                chatId: chatId,
                title: title,
                body: body,
                isSilent: isSilent,
            ))
        }
    }

    /// Called on every foreground transition (see `BetterTGApp`). Rebasing the backlog gate here is
    /// what keeps the notifications TDLib replays on reconnect from bannering - only messages that
    /// land while the app is genuinely in front of the user do.
    @MainActor func noteAppBecameActive() {
        notificationBannerActiveSince = Date()
    }

    @MainActor func openInAppNotification(_ banner: TelegramInAppNotificationBanner) {
        dismissInAppNotification()
        Task { @MainActor [weak self] in
            guard let self, let chat = await getCustomChat(from: banner.chatId) else { return }
            openChatReplacingStack(chat)
        }
    }

    @MainActor func dismissInAppNotification() {
        inAppNotificationDismissTask?.cancel()
        inAppNotificationDismissTask = nil
        advanceInAppNotificationQueue()
    }

    // MARK: Private

    private static let inAppNotificationDisplayDuration = Duration.seconds(4)

    /// Tolerance for skew between the device wall clock and TDLib's server-set `notification.date`
    /// when deciding whether a notification predates the last foreground transition.
    private static let notificationBannerBacklogGrace: TimeInterval = 3

    /// Mirrors `MacSessionModel+Notifications.swift`'s `notificationBody(_:)` - kept in sync by
    /// hand since the two run against different live connections (iOS's single global `TDLib`
    /// singleton vs. each Mac window's own `MacSessionModel.service`), not because the logic itself
    /// should ever actually differ between platforms.
    private static func inAppNotificationBody(_ notification: TDLibKit.Notification) -> String? {
        let showsPreview = TelegramInAppNotificationPreferences.previewsEnabled
        switch notification.type {
        case .notificationTypeNewMessage(let value):
            guard !value.message.isOutgoing else { return nil }
            return value.showPreview && showsPreview
                ? telegramMessageContentDescription(value.message)
                : "You have a new message."
        case .notificationTypeNewPushMessage(let value):
            guard !value.isOutgoing else { return nil }
            return showsPreview && !value.senderName.isEmpty
                ? "New message from \(value.senderName)."
                : "You have a new message."
        case .notificationTypeNewCall, .notificationTypeNewSecretChat:
            return nil
        }
    }

    @MainActor private func enqueueInAppNotification(_ banner: TelegramInAppNotificationBanner) {
        guard inAppNotificationBanner?.id != banner.id,
              !pendingInAppNotificationBanners.contains(where: { $0.id == banner.id })
        else { return }

        // One banner per chat, like Telegram-iOS's `removeItemsWithGroupingKey(peerId)`: a newer
        // message from a chat refreshes its banner in place (or replaces its queued one) instead of
        // stacking another behind it.
        if inAppNotificationBanner?.chatId == banner.chatId {
            presentInAppNotification(banner)
            return
        }
        pendingInAppNotificationBanners.removeAll { $0.chatId == banner.chatId }
        guard inAppNotificationBanner == nil else {
            pendingInAppNotificationBanners.append(banner)
            return
        }
        presentInAppNotification(banner)
    }

    @MainActor private func presentInAppNotification(_ banner: TelegramInAppNotificationBanner) {
        inAppNotificationBanner = banner
        if TelegramInAppNotificationPreferences.soundEnabled {
            ServiceSoundManager.shared.playIncomingMessageIfAppropriate(isMuted: banner.isSilent)
        }
        if !banner.isSilent, TelegramInAppNotificationPreferences.vibrateEnabled {
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
        inAppNotificationDismissTask?.cancel()
        inAppNotificationDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.inAppNotificationDisplayDuration)
            guard !Task.isCancelled else { return }
            self?.advanceInAppNotificationQueue()
        }
    }

    @MainActor private func advanceInAppNotificationQueue() {
        guard !pendingInAppNotificationBanners.isEmpty else {
            inAppNotificationBanner = nil
            return
        }
        presentInAppNotification(pendingInAppNotificationBanners.removeFirst())
    }
}
