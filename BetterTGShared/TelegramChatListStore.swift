// TelegramChatListStore.swift

import Combine
import Foundation
@preconcurrency import TDLibKit

// MARK: - ChatListItemKind

enum ChatListItemKind: Sendable, Equatable {
    case privateChat
    case group
    case channel
    case secretChat

    // MARK: Lifecycle

    init(_ type: ChatType) {
        self =
            switch type {
            case .chatTypeBasicGroup:
                .group
            case .chatTypeSupergroup(let supergroup):
                supergroup.isChannel ? .channel : .group
            case .chatTypeSecret:
                .secretChat
            case .chatTypePrivate:
                .privateChat
            }
    }

    // MARK: Internal

    var accessibilityTitle: String? {
        switch self {
        case .group: "Group"
        case .channel: "Channel"
        case .secretChat: "Secret chat"
        case .privateChat: nil
        }
    }

    var systemImage: String {
        switch self {
        case .group: "person.2.fill"
        case .channel: "megaphone.fill"
        case .secretChat: "lock.fill"
        case .privateChat: "bubble.left.fill"
        }
    }
}

// MARK: - ChatListCommunity

enum ChatListCommunity: Sendable, Equatable, Hashable {
    case basicGroup(Int64)
    case supergroup(Int64)

    // MARK: Lifecycle

    init?(_ type: ChatType) {
        switch type {
        case .chatTypeBasicGroup(let value):
            self = .basicGroup(value.basicGroupId)
        case .chatTypeSupergroup(let value):
            self = .supergroup(value.supergroupId)
        case .chatTypePrivate, .chatTypeSecret:
            return nil
        }
    }
}

// MARK: - ChatListMembership

enum ChatListMembership: Sendable, Equatable {
    case member
    case creator
    case notMember

    // MARK: Lifecycle

    init(_ status: ChatMemberStatus) {
        self =
            switch status {
            case .chatMemberStatusCreator:
                .creator
            case .chatMemberStatusAdministrator, .chatMemberStatusMember:
                .member
            case .chatMemberStatusRestricted(let value):
                value.isMember ? .member : .notMember
            case .chatMemberStatusBanned, .chatMemberStatusLeft:
                .notMember
            }
    }
}

func telegramCanPostMessages(in supergroup: Supergroup) -> Bool {
    telegramCanPostMessages(isChannel: supergroup.isChannel, status: supergroup.status)
}

func telegramCanPostMessages(isChannel: Bool, status: ChatMemberStatus) -> Bool {
    guard isChannel else {
        switch status {
        case .chatMemberStatusBanned, .chatMemberStatusLeft:
            return false
        case .chatMemberStatusRestricted(let value):
            return value.isMember
        case .chatMemberStatusAdministrator, .chatMemberStatusCreator, .chatMemberStatusMember:
            return true
        }
    }

    switch status {
    case .chatMemberStatusCreator:
        return true
    case .chatMemberStatusAdministrator(let value):
        return value.rights.canPostMessages
    case .chatMemberStatusBanned, .chatMemberStatusLeft, .chatMemberStatusMember,
         .chatMemberStatusRestricted:
        return false
    }
}

// MARK: - ChatListItemState

struct ChatListItemState: Sendable, Equatable {
    let chatId: Int64
    var title: String
    var kind: ChatListItemKind
    var positions: [ChatPosition]
    var unreadCount: Int
    var lastMessage: Message?
    var draftMessage: DraftMessage?
    var notificationSettings: ChatNotificationSettings?
    var lastReadInboxMessageId: Int64
    var lastReadOutboxMessageId: Int64
    var isMarkedAsUnread: Bool
    var canBeDeletedOnlyForSelf: Bool
    var canBeDeletedForAllUsers: Bool
    var community: ChatListCommunity?
    var membership: ChatListMembership?
    var canPostMessages: Bool?
    /// The other person's user id, for private and secret chats only - `nil` for groups/channels.
    var userId: Int64?

    var hasUnreadMessages: Bool {
        unreadCount > 0 || isMarkedAsUnread
    }

    var actionPolicy: TelegramChatActionPolicy {
        TelegramChatActionPolicy(
            kind: kind,
            membership: membership,
            canBeDeletedOnlyForSelf: canBeDeletedOnlyForSelf,
            canBeDeletedForAllUsers: canBeDeletedForAllUsers,
        )
    }

    func position(in list: ChatList) -> ChatPosition? {
        positions.first { $0.list == list }
    }
}

extension ChatListItemState {
    /// Builds an item for a `Chat` that isn't in the store's snapshot yet (e.g. resolved via a deep
    /// link or search). `membership` should come from `TelegramService.resolveMembership(for:)`
    /// rather than being left `nil`, or Leave/Delete actions gated on membership won't show up.
    init(_ chat: Chat, membership: ChatListMembership?, canPostMessages: Bool? = nil) {
        let userId: Int64? =
            switch chat.type {
            case .chatTypePrivate(let value): value.userId
            case .chatTypeSecret(let value): value.userId
            case .chatTypeBasicGroup, .chatTypeSupergroup: nil
            }

        self.init(
            chatId: chat.id,
            title: chat.title,
            kind: ChatListItemKind(chat.type),
            positions: chat.positions,
            unreadCount: chat.unreadCount,
            lastMessage: chat.lastMessage,
            draftMessage: chat.draftMessage,
            notificationSettings: chat.notificationSettings,
            lastReadInboxMessageId: chat.lastReadInboxMessageId,
            lastReadOutboxMessageId: chat.lastReadOutboxMessageId,
            isMarkedAsUnread: chat.isMarkedAsUnread,
            canBeDeletedOnlyForSelf: chat.canBeDeletedOnlyForSelf,
            canBeDeletedForAllUsers: chat.canBeDeletedForAllUsers,
            community: ChatListCommunity(chat.type),
            membership: membership,
            canPostMessages: canPostMessages,
            userId: userId,
        )
    }
}

extension TelegramService {
    /// Fetches the current user's membership in `chat`'s group/supergroup directly from TDLib,
    /// for chats not yet known to `TelegramChatListStore` (its `memberships` cache is only ever
    /// populated by `updateBasicGroup`/`updateSupergroup` push updates).
    func resolveMembership(for chat: Chat) async -> ChatListMembership? {
        switch ChatListCommunity(chat.type) {
        case .basicGroup(let id):
            guard let group = try? await getBasicGroup(basicGroupId: id) else { return nil }
            return ChatListMembership(group.status)
        case .supergroup(let id):
            guard let supergroup = try? await getSupergroup(supergroupId: id) else { return nil }
            return ChatListMembership(supergroup.status)
        case nil:
            return nil
        }
    }
}

// MARK: - ChatListSnapshot

struct ChatListSnapshot: Sendable, Equatable {
    static let empty = ChatListSnapshot(version: 0, chatFolders: [], mainChatListPosition: 0, items: [:])

    var version: UInt64
    var chatFolders: [ChatFolderInfo]
    var mainChatListPosition: Int
    var items: [Int64: ChatListItemState]

    func chatIds(in list: ChatList) -> [Int64] {
        var positionedItems = [(item: ChatListItemState, position: ChatPosition)]()
        for item in items.values {
            if let position = item.position(in: list) {
                positionedItems.append((item, position))
            }
        }
        return positionedItems
            .sorted { $0.position.order > $1.position.order }
            .map(\.item.chatId)
    }
}

// MARK: - TelegramChatListStore

final class TelegramChatListStore: @unchecked Sendable {
    // MARK: Internal

    var publisher: AnyPublisher<ChatListSnapshot, Never> {
        subject.eraseToAnyPublisher()
    }

    func reduce(_ update: Update) {
        queue.async {
            self.reduceOnQueue(update)
        }
    }

    func mergeChats(_ chats: [Chat]) {
        queue.async {
            self.mergeChatsOnQueue(chats)
        }
    }

    /// Blocks until all previously-enqueued mutations have applied. For deterministic tests only.
    func waitForPendingWork() {
        queue.sync {}
    }

    // MARK: Private

    private let queue = DispatchQueue(label: "com.gruiachiscop.BetterTG.telegram-chatlist")
    private var memberships = [ChatListCommunity: ChatListMembership]()
    private var postingPermissions = [ChatListCommunity: Bool]()
    private let subject = CurrentValueSubject<ChatListSnapshot, Never>(.empty)

    private func reduceOnQueue(_ update: Update) {
        dispatchPrecondition(condition: .onQueue(queue))
        var state = subject.value
        switch update {
        case .updateChatFolders(let value):
            state.chatFolders = value.chatFolders
            state.mainChatListPosition = value.mainChatListPosition
        case .updateChatReadInbox(let value):
            guard var item = state.items[value.chatId] else { return }
            item.unreadCount = value.unreadCount
            item.lastReadInboxMessageId = value.lastReadInboxMessageId
            state.items[value.chatId] = item
        case .updateChatReadOutbox(let value):
            guard var item = state.items[value.chatId] else { return }
            item.lastReadOutboxMessageId = value.lastReadOutboxMessageId
            state.items[value.chatId] = item
        case .updateChatIsMarkedAsUnread(let value):
            guard var item = state.items[value.chatId] else { return }
            item.isMarkedAsUnread = value.isMarkedAsUnread
            state.items[value.chatId] = item
        case .updateNewChat(let value):
            let community = ChatListCommunity(value.chat.type)
            state.items[value.chat.id] = ChatListItemState(
                value.chat,
                membership: community.flatMap { memberships[$0] },
                canPostMessages: community.flatMap { postingPermissions[$0] },
            )
        case .updateBasicGroup(let value):
            let community = ChatListCommunity.basicGroup(value.basicGroup.id)
            memberships[community] = ChatListMembership(value.basicGroup.status)
            guard updateCommunityAccess(in: &state, for: community) else { return }
        case .updateSupergroup(let value):
            let community = ChatListCommunity.supergroup(value.supergroup.id)
            memberships[community] = ChatListMembership(value.supergroup.status)
            postingPermissions[community] = telegramCanPostMessages(in: value.supergroup)
            guard updateCommunityAccess(in: &state, for: community) else { return }
        case .updateChatPosition(let value):
            guard var item = state.items[value.chatId] else { return }
            item.positions.removeAll { $0.list == value.position.list }
            if value.position.order != 0 {
                item.positions.append(value.position)
            }
            state.items[value.chatId] = item
        case .updateChatDraftMessage(let value):
            guard var item = state.items[value.chatId] else { return }
            item.draftMessage = value.draftMessage
            item.positions = value.positions
            state.items[value.chatId] = item
        case .updateChatLastMessage(let value):
            guard var item = state.items[value.chatId] else { return }
            item.lastMessage = value.lastMessage
            item.positions = value.positions
            state.items[value.chatId] = item
        case .updateChatNotificationSettings(let value):
            guard var item = state.items[value.chatId] else { return }
            item.notificationSettings = value.notificationSettings
            state.items[value.chatId] = item
        case .updateChatTitle(let value):
            guard var item = state.items[value.chatId] else { return }
            item.title = value.title
            state.items[value.chatId] = item
        default:
            return
        }
        state.version += 1
        subject.send(state)
    }

    private func mergeChatsOnQueue(_ chats: [Chat]) {
        dispatchPrecondition(condition: .onQueue(queue))
        var state = subject.value
        var changed = false
        for chat in chats {
            if var existing = state.items[chat.id] {
                let knownLists = Set(existing.positions.map(\.list))
                let missingPositions = chat.positions.filter { !knownLists.contains($0.list) }
                guard !missingPositions.isEmpty else { continue }
                existing.positions.append(contentsOf: missingPositions)
                state.items[chat.id] = existing
                changed = true
            } else {
                let community = ChatListCommunity(chat.type)
                state.items[chat.id] = ChatListItemState(
                    chat,
                    membership: community.flatMap { memberships[$0] },
                    canPostMessages: community.flatMap { postingPermissions[$0] },
                )
                changed = true
            }
        }
        guard changed else { return }
        state.version += 1
        subject.send(state)
    }

    private func updateCommunityAccess(in state: inout ChatListSnapshot, for community: ChatListCommunity) -> Bool {
        guard let membership = memberships[community] else { return false }
        let canPostMessages = postingPermissions[community]
        let chatIds = state.items.compactMap { chatId, item in
            item.community == community
                && (item.membership != membership || item.canPostMessages != canPostMessages)
                ? chatId
                : nil
        }
        var changed = false
        for chatId in chatIds {
            guard var item = state.items[chatId] else { continue }
            item.membership = membership
            item.canPostMessages = canPostMessages
            state.items[chatId] = item
            changed = true
        }
        return changed
    }
}
