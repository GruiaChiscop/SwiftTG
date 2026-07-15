import Combine
@preconcurrency import TDLibKit

struct ChatListItemState: Sendable, Equatable {
    let chatId: Int64
    var title: String
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

    var hasUnreadMessages: Bool {
        unreadCount > 0 || isMarkedAsUnread
    }

    func position(in list: ChatList) -> ChatPosition? {
        positions.first { $0.list == list }
    }
}

struct ChatListSnapshot: Sendable, Equatable {
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
            .map { $0.item.chatId }
    }

    static let empty = ChatListSnapshot(version: 0, chatFolders: [], mainChatListPosition: 0, items: [:])
}

final class TelegramChatListStore: @unchecked Sendable {
    var publisher: AnyPublisher<ChatListSnapshot, Never> {
        subject.eraseToAnyPublisher()
    }

    func reduce(_ update: Update) {
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
            state.items[value.chat.id] = ChatListItemState(
                chatId: value.chat.id,
                title: value.chat.title,
                positions: value.chat.positions,
                unreadCount: value.chat.unreadCount,
                lastMessage: value.chat.lastMessage,
                draftMessage: value.chat.draftMessage,
                notificationSettings: value.chat.notificationSettings,
                lastReadInboxMessageId: value.chat.lastReadInboxMessageId,
                lastReadOutboxMessageId: value.chat.lastReadOutboxMessageId,
                isMarkedAsUnread: value.chat.isMarkedAsUnread,
                canBeDeletedOnlyForSelf: value.chat.canBeDeletedOnlyForSelf,
                canBeDeletedForAllUsers: value.chat.canBeDeletedForAllUsers,
            )
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

    func mergeChats(_ chats: [Chat]) {
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
                state.items[chat.id] = ChatListItemState(
                    chatId: chat.id,
                    title: chat.title,
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
                )
                changed = true
            }
        }
        guard changed else { return }
        state.version += 1
        subject.send(state)
    }

    private let subject = CurrentValueSubject<ChatListSnapshot, Never>(.empty)
}
