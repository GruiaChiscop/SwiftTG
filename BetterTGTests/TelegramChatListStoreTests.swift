// TelegramChatListStoreTests.swift

@testable import BetterTG
import Combine
import TDLibKit
import Testing

struct TelegramChatListStoreTests {
    // MARK: Internal

    @Test func `bootstrap merge populates and orders an initially empty store`() throws {
        let store = TelegramChatListStore()

        store.mergeChats([
            TDLibFixtures.chat(id: 1, order: 100),
            TDLibFixtures.chat(id: 2, order: 300),
            TDLibFixtures.chat(id: 3, order: 200),
        ])

        let snapshot = try currentSnapshot(of: store)
        #expect(snapshot.version == 1)
        #expect(snapshot.chatIds(in: .chatListMain) == [2, 3, 1])
    }

    @Test func `bootstrap merge does not overwrite newer live state`() throws {
        let store = TelegramChatListStore()
        let staleChat = TDLibFixtures.chat(id: 7, order: 100, unreadCount: 1)
        store.mergeChats([staleChat])
        store.reduce(.updateChatReadInbox(.init(
            chatId: 7,
            lastReadInboxMessageId: 10,
            unreadCount: 9,
        )))
        let versionAfterLiveUpdate = try currentSnapshot(of: store).version

        store.mergeChats([staleChat])

        let snapshot = try currentSnapshot(of: store)
        #expect(snapshot.items[7]?.unreadCount == 9)
        #expect(snapshot.items[7]?.lastReadInboxMessageId == 10)
        #expect(snapshot.version == versionAfterLiveUpdate)
    }

    @Test func `bootstrap merge adds a newly discovered list position without overwriting live state`() throws {
        let store = TelegramChatListStore()
        store.mergeChats([TDLibFixtures.chat(id: 7, order: 100, unreadCount: 1)])
        store.reduce(.updateChatReadInbox(.init(
            chatId: 7,
            lastReadInboxMessageId: 10,
            unreadCount: 9,
        )))

        store.mergeChats([TDLibFixtures.chat(
            id: 7,
            order: 80,
            unreadCount: 1,
            list: .chatListFolder(.init(chatFolderId: 42)),
        )])

        let snapshot = try currentSnapshot(of: store)
        #expect(snapshot.items[7]?.unreadCount == 9)
        #expect(snapshot.chatIds(in: .chatListMain) == [7])
        #expect(snapshot.chatIds(in: .chatListFolder(.init(chatFolderId: 42))) == [7])
    }

    @Test func `zero order removes chat only from the affected list`() throws {
        let store = TelegramChatListStore()
        let chat = TDLibFixtures.chat(id: 12, order: 100)
        store.mergeChats([chat])
        store.reduce(.updateChatPosition(.init(
            chatId: chat.id,
            position: TDLibFixtures.position(order: 0),
        )))

        let snapshot = try currentSnapshot(of: store)
        #expect(snapshot.chatIds(in: .chatListMain).isEmpty)
        #expect(snapshot.items[chat.id] != nil)
    }

    @Test func `updates for unknown chats are ignored until bootstrap`() throws {
        let store = TelegramChatListStore()
        store.reduce(.updateChatReadInbox(.init(
            chatId: 99,
            lastReadInboxMessageId: 1,
            unreadCount: 3,
        )))

        #expect(try currentSnapshot(of: store) == .empty)
    }

    @Test func `marked unread state follows live update`() throws {
        let store = TelegramChatListStore()
        store.mergeChats([TDLibFixtures.chat(id: 42, order: 100)])

        store.reduce(.updateChatIsMarkedAsUnread(.init(chatId: 42, isMarkedAsUnread: true)))

        let item = try currentSnapshot(of: store).items[42]
        #expect(item?.isMarkedAsUnread == true)
        #expect(item?.hasUnreadMessages == true)
    }

    @Test func `real unread count is exposed as unread without a manual marker`() throws {
        let store = TelegramChatListStore()
        store.mergeChats([TDLibFixtures.chat(id: 43, order: 100, unreadCount: 5)])

        let item = try currentSnapshot(of: store).items[43]
        #expect(item?.isMarkedAsUnread == false)
        #expect(item?.hasUnreadMessages == true)
    }

    // MARK: Private

    private func currentSnapshot(of store: TelegramChatListStore) throws -> ChatListSnapshot {
        var result: ChatListSnapshot?
        let cancellable = store.publisher.first().sink { result = $0 }
        withExtendedLifetime(cancellable) {}
        return try #require(result)
    }
}
