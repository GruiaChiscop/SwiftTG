// MacConversationHeader.swift

import Foundation
import SwiftUI
import TDLibKit

// MARK: - MacConversationHeader

struct MacConversationHeader: View {
    // MARK: Internal

    let title: String
    let status: String?
    let onOpenInfo: () -> Void

    var body: some View {
        Button(action: onOpenInfo) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)

                if let status, !status.isEmpty {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens chat information")
    }
}

// MARK: - MacSessionModel Conversation Header

extension MacSessionModel {
    var conversationHeaderStatus: String? {
        if conversationHeaderActivities.count > 1 {
            return "\(conversationHeaderActivities.count) people are active…"
        }
        if let action = conversationHeaderActivities.values.first {
            return macConversationActionDescription(action)
        }
        return conversationHeaderBaseStatus
    }

    func prepareConversationHeader(for chatId: Int64, fallbackKind: ChatListItemKind?) {
        conversationHeaderTask?.cancel()
        conversationHeaderTask = nil
        openedChatType = nil
        conversationHeaderActivities = [:]
        conversationHeaderBaseStatus = fallbackKind.flatMap(macConversationFallbackStatus)

        conversationHeaderTask = Task { [weak self] in
            guard let self,
                  let chat = try? await service.getChat(chatId: chatId),
                  !Task.isCancelled,
                  openedChatId == chatId
            else { return }

            openedChatType = chat.type
            switch chat.type {
            case .chatTypePrivate(let privateChat):
                guard let user = try? await service.getUser(userId: privateChat.userId),
                      !Task.isCancelled,
                      openedChatId == chatId
                else { return }
                conversationHeaderBaseStatus = macConversationUserStatus(user)
            case .chatTypeSecret(let secretChat):
                guard let user = try? await service.getUser(userId: secretChat.userId),
                      !Task.isCancelled,
                      openedChatId == chatId
                else { return }
                conversationHeaderBaseStatus = macConversationUserStatus(user)
            case .chatTypeBasicGroup(let basicGroupChat):
                guard let group = try? await service.getBasicGroup(basicGroupId: basicGroupChat.basicGroupId),
                      !Task.isCancelled,
                      openedChatId == chatId
                else { return }
                let fullInfo = group.memberCount == 0
                    ? try? await service.getBasicGroupFullInfo(basicGroupId: basicGroupChat.basicGroupId)
                    : nil
                let memberCount = group.memberCount > 0 ? group.memberCount : fullInfo?.members.count ?? 0
                conversationHeaderBaseStatus = macConversationGroupStatus(memberCount: memberCount)
            case .chatTypeSupergroup(let supergroupChat):
                guard let group = try? await service.getSupergroup(supergroupId: supergroupChat.supergroupId),
                      !Task.isCancelled,
                      openedChatId == chatId
                else { return }
                let fullInfo = group.memberCount == 0
                    ? try? await service.getSupergroupFullInfo(supergroupId: supergroupChat.supergroupId)
                    : nil
                let memberCount = group.memberCount > 0 ? group.memberCount : fullInfo?.memberCount ?? 0
                conversationHeaderBaseStatus = macConversationSupergroupStatus(
                    isChannel: group.isChannel,
                    memberCount: memberCount,
                )
            }
        }
    }

    func handleConversationHeaderUpdate(_ update: Update) {
        guard let openedChatType else { return }

        switch update {
        case .updateUserStatus(let value):
            guard macConversationUserId(openedChatType) == value.userId else { return }
            conversationHeaderBaseStatus = macUserPresenceDescription(value.status)
        case .updateUser(let value):
            guard macConversationUserId(openedChatType) == value.user.id else { return }
            conversationHeaderBaseStatus = macConversationUserStatus(value.user)
        case .updateBasicGroup(let value):
            guard case .chatTypeBasicGroup(let chatType) = openedChatType,
                  chatType.basicGroupId == value.basicGroup.id
            else { return }
            conversationHeaderBaseStatus = macConversationGroupStatus(memberCount: value.basicGroup.memberCount)
        case .updateSupergroup(let value):
            guard case .chatTypeSupergroup(let chatType) = openedChatType,
                  chatType.supergroupId == value.supergroup.id
            else { return }
            conversationHeaderBaseStatus = macConversationSupergroupStatus(
                isChannel: value.supergroup.isChannel,
                memberCount: value.supergroup.memberCount,
            )
        case .updateBasicGroupFullInfo(let value):
            guard case .chatTypeBasicGroup(let chatType) = openedChatType,
                  chatType.basicGroupId == value.basicGroupId
            else { return }
            conversationHeaderBaseStatus = macConversationGroupStatus(
                memberCount: value.basicGroupFullInfo.members.count,
            )
        case .updateSupergroupFullInfo(let value):
            guard case .chatTypeSupergroup(let chatType) = openedChatType,
                  chatType.supergroupId == value.supergroupId
            else { return }
            conversationHeaderBaseStatus = macConversationSupergroupStatus(
                isChannel: chatType.isChannel,
                memberCount: value.supergroupFullInfo.memberCount,
            )
        case .updateChatAction(let value):
            guard value.chatId == openedChatId else { return }
            if case .chatActionCancel = value.action {
                conversationHeaderActivities[value.senderId] = nil
            } else {
                conversationHeaderActivities[value.senderId] = value.action
            }
        default:
            break
        }
    }
}

// MARK: - Formatting

private func macConversationFallbackStatus(_ kind: ChatListItemKind) -> String? {
    switch kind {
    case .privateChat: nil
    case .secretChat: "Secret chat"
    case .group: "Group"
    case .channel: "Channel"
    }
}

private func macConversationUserId(_ chatType: ChatType) -> Int64? {
    switch chatType {
    case .chatTypePrivate(let value): value.userId
    case .chatTypeSecret(let value): value.userId
    case .chatTypeBasicGroup, .chatTypeSupergroup: nil
    }
}

func macConversationUserStatus(_ user: User) -> String {
    switch user.type {
    case .userTypeBot: "Bot"
    case .userTypeDeleted: "Deleted account"
    case .userTypeRegular, .userTypeUnknown: macUserPresenceDescription(user.status)
    }
}

private func macUserPresenceDescription(
    _ status: UserStatus,
    now: Foundation.Date = Foundation.Date(),
    calendar: Calendar = .autoupdatingCurrent,
) -> String {
    switch status {
    case .userStatusOnline:
        return "Online"
    case .userStatusOffline(let value):
        guard value.wasOnline > 0 else { return "Offline" }
        let date = Foundation.Date(timeIntervalSince1970: TimeInterval(value.wasOnline))
        if calendar.isDate(date, inSameDayAs: now) {
            return "Last seen today at \(date.formatted(date: .omitted, time: .shortened))"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday)
        {
            return "Last seen yesterday at \(date.formatted(date: .omitted, time: .shortened))"
        }
        return "Last seen \(date.formatted(date: .abbreviated, time: .shortened))"
    case .userStatusRecently:
        return "Last seen recently"
    case .userStatusLastWeek:
        return "Last seen within a week"
    case .userStatusLastMonth:
        return "Last seen within a month"
    case .userStatusEmpty:
        return "Last seen a long time ago"
    }
}

private func macConversationGroupStatus(memberCount: Int) -> String {
    guard memberCount > 0 else { return "Group" }
    return memberCount == 1 ? "1 member" : "\(memberCount.formatted()) members"
}

private func macConversationSupergroupStatus(isChannel: Bool, memberCount: Int) -> String {
    guard memberCount > 0 else { return isChannel ? "Channel" : "Group" }
    if isChannel {
        return memberCount == 1 ? "1 subscriber" : "\(memberCount.formatted()) subscribers"
    }
    return macConversationGroupStatus(memberCount: memberCount)
}

private func macConversationActionDescription(_ action: ChatAction) -> String? {
    switch action {
    case .chatActionTyping: "Typing…"
    case .chatActionRecordingVideo: "Recording a video…"
    case .chatActionUploadingVideo: "Uploading a video…"
    case .chatActionRecordingVoiceNote: "Recording a voice message…"
    case .chatActionUploadingVoiceNote: "Uploading a voice message…"
    case .chatActionUploadingPhoto: "Uploading a photo…"
    case .chatActionUploadingDocument: "Uploading a file…"
    case .chatActionChoosingSticker: "Choosing a sticker…"
    case .chatActionChoosingLocation: "Choosing a location…"
    case .chatActionChoosingContact: "Choosing a contact…"
    case .chatActionStartPlayingGame: "Playing a game…"
    case .chatActionRecordingVideoNote: "Recording a video message…"
    case .chatActionUploadingVideoNote: "Uploading a video message…"
    case .chatActionWatchingAnimations: "Watching an animation…"
    case .chatActionCancel: nil
    }
}
