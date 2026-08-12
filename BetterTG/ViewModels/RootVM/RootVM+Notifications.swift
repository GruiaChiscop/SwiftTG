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
        navigate(to: .customChat(customChat, messageId: nil))
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
        guard UIApplication.shared.applicationState == .active,
              currentlyOpenChatId != group.chatId
        else { return }

        for notification in group.addedNotifications {
            // Matches `MacSessionModel+Notifications.swift`'s own freshness check - avoids
            // surfacing a banner for a notification that's actually old news (e.g. a burst of
            // updates catching the client up after a brief connectivity gap).
            guard Date().timeIntervalSince1970 - TimeInterval(notification.date) < 3600,
                  let body = Self.inAppNotificationBody(notification)
            else { continue }

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
    }

    @MainActor func openInAppNotification(_ banner: TelegramInAppNotificationBanner) {
        dismissInAppNotification()
        Task { @MainActor [weak self] in
            guard let self, let chat = await getCustomChat(from: banner.chatId) else { return }
            navigate(to: .customChat(chat))
        }
    }

    @MainActor func dismissInAppNotification() {
        inAppNotificationDismissTask?.cancel()
        inAppNotificationDismissTask = nil
        advanceInAppNotificationQueue()
    }

    // MARK: Private

    private static let inAppNotificationDisplayDuration: Duration = .seconds(4)

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
