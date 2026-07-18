// TelegramServiceMessage.swift

import Foundation
import TDLibKit

enum TelegramServiceMessage {
    // MARK: Internal

    static func isServiceMessage(_ content: MessageContent) -> Bool {
        switch content {
        case .messageBasicGroupChatCreate,
             .messageChatAddMembers,
             .messageChatChangePhoto,
             .messageChatChangeTitle,
             .messageChatDeleteMember,
             .messageChatDeletePhoto,
             .messageChatJoinByLink,
             .messageChatJoinByRequest,
             .messageChatOwnerChanged,
             .messageChatOwnerLeft,
             .messageChatSetMessageAutoDeleteTime,
             .messageChatUpgradeFrom,
             .messageChatUpgradeTo,
             .messageCustomServiceAction,
             .messagePinMessage,
             .messageScreenshotTaken,
             .messageSupergroupChatCreate:
            true
        default:
            false
        }
    }

    static func description(service: any TelegramService, message: Message) async -> String? {
        guard isServiceMessage(message.content) else { return nil }
        let actor: String =
            if message.isOutgoing {
                "You"
            } else {
                await TelegramSenderName.displayName(service: service, senderId: message.senderId) ?? "Someone"
            }

        switch message.content {
        case .messageBasicGroupChatCreate(let content):
            return "\(actor) created the group \(content.title)"
        case .messageSupergroupChatCreate(let content):
            return "\(actor) created \(content.title)"
        case .messageChatChangeTitle(let content):
            return "\(actor) changed the group name to \(content.title)"
        case .messageChatChangePhoto:
            return "\(actor) changed the group photo"
        case .messageChatDeletePhoto:
            return "\(actor) removed the group photo"
        case .messageChatOwnerLeft(let content):
            guard content.newOwnerUserId != 0,
                  let newOwner = await userName(service: service, userId: content.newOwnerUserId)
            else { return "The group owner left" }
            return "The group owner left. \(newOwner) will become the new owner"
        case .messageChatOwnerChanged(let content):
            let newOwner = await userName(service: service, userId: content.newOwnerUserId) ?? "another member"
            return "\(actor) transferred group ownership to \(newOwner)"
        case .messageChatAddMembers(let content):
            if content.memberUserIds.count == 1,
               case .messageSenderUser(let sender) = message.senderId,
               sender.userId == content.memberUserIds[0]
            {
                return "\(actor) joined the group"
            }
            let names = await userNames(service: service, userIds: content.memberUserIds)
            return "\(actor) added \(names.isEmpty ? "new members" : names.joined(separator: ", "))"
        case .messageChatJoinByLink:
            return "\(actor) joined the group via an invite link"
        case .messageChatJoinByRequest:
            return "\(actor) joined the group after their request was approved"
        case .messageChatDeleteMember(let content):
            if case .messageSenderUser(let sender) = message.senderId, sender.userId == content.userId {
                return "\(actor) left the group"
            }
            let member = await userName(service: service, userId: content.userId) ?? "a member"
            return "\(actor) removed \(member)"
        case .messageChatUpgradeTo:
            return "The group was upgraded to a supergroup"
        case .messageChatUpgradeFrom:
            return "The group was upgraded to a supergroup"
        case .messagePinMessage:
            return "\(actor) pinned a message"
        case .messageScreenshotTaken:
            return "\(actor) took a screenshot"
        case .messageChatSetMessageAutoDeleteTime(let content):
            if content.messageAutoDeleteTime == 0 {
                return "\(actor) disabled auto-delete"
            }
            return "\(actor) set messages to auto-delete after \(durationDescription(content.messageAutoDeleteTime))"
        case .messageCustomServiceAction(let content):
            return content.text
        default:
            return nil
        }
    }

    // MARK: Private

    private static func userName(service: any TelegramService, userId: Int64) async -> String? {
        guard let user = try? await service.getUser(userId: userId) else { return nil }
        return telegramUserDisplayName(user)
    }

    private static func userNames(service: any TelegramService, userIds: [Int64]) async -> [String] {
        var names = [String]()
        for userId in userIds.prefix(10) {
            if let name = await userName(service: service, userId: userId) {
                names.append(name)
            }
        }
        if userIds.count > 10 {
            names.append("\(userIds.count - 10) others")
        }
        return names
    }

    private static func durationDescription(_ seconds: Int) -> String {
        if seconds.isMultiple(of: 86400) {
            let days = seconds / 86400
            return "\(days) \(days == 1 ? "day" : "days")"
        }
        if seconds.isMultiple(of: 3600) {
            let hours = seconds / 3600
            return "\(hours) \(hours == 1 ? "hour" : "hours")"
        }
        if seconds.isMultiple(of: 60) {
            let minutes = seconds / 60
            return "\(minutes) \(minutes == 1 ? "minute" : "minutes")"
        }
        return "\(seconds) \(seconds == 1 ? "second" : "seconds")"
    }
}
