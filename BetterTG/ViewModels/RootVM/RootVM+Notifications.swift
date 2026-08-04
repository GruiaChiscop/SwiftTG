// RootVM+Notifications.swift

import Foundation
import TDLibKit

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
