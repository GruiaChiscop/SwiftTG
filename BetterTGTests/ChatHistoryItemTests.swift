// ChatHistoryItemTests.swift

@testable import BetterTG
import Testing

@MainActor struct ChatHistoryItemTests {
    @Test func `empty history produces no items`() {
        let items = ChatHistoryItem.makeItems(
            messages: [],
            unreadMessageId: nil,
            unreadCount: 0,
            unreadHeaderVoiceOverFocusRequest: 0,
        )

        #expect(items.isEmpty)
    }

    @Test func `first message always starts a day header`() {
        let message = makeMessage(id: 1, date: baseDate)

        let items = ChatHistoryItem.makeItems(
            messages: [message],
            unreadMessageId: nil,
            unreadCount: 0,
            unreadHeaderVoiceOverFocusRequest: 0,
        )

        #expect(items.map(\.id) == [.day(1), .message(1)])
    }

    @Test func `messages on the same day do not repeat the day header`() {
        let messages = [
            makeMessage(id: 1, date: baseDate),
            makeMessage(id: 2, date: baseDate + 60),
            makeMessage(id: 3, date: baseDate + 120),
        ]

        let items = ChatHistoryItem.makeItems(
            messages: messages,
            unreadMessageId: nil,
            unreadCount: 0,
            unreadHeaderVoiceOverFocusRequest: 0,
        )

        #expect(items.map(\.id) == [.day(1), .message(1), .message(2), .message(3)])
    }

    @Test func `a message on a new calendar day gets its own header`() {
        let messages = [
            makeMessage(id: 1, date: baseDate),
            makeMessage(id: 2, date: baseDate + twoDays),
        ]

        let items = ChatHistoryItem.makeItems(
            messages: messages,
            unreadMessageId: nil,
            unreadCount: 0,
            unreadHeaderVoiceOverFocusRequest: 0,
        )

        #expect(items.map(\.id) == [.day(1), .message(1), .day(2), .message(2)])
    }

    @Test func `unread header is inserted immediately before the first unread message`() {
        let messages = [
            makeMessage(id: 1, date: baseDate),
            makeMessage(id: 2, date: baseDate + 60),
            makeMessage(id: 3, date: baseDate + 120),
        ]

        let items = ChatHistoryItem.makeItems(
            messages: messages,
            unreadMessageId: 2,
            unreadCount: 5,
            unreadHeaderVoiceOverFocusRequest: 3,
        )

        #expect(items.map(\.id) == [.day(1), .message(1), .unread(2), .message(2), .message(3)])

        guard case .unread(let count, let focusRequest) = items[2].kind else {
            Issue.record("expected an unread item")
            return
        }
        #expect(count == 5)
        #expect(focusRequest == 3)
    }

    @Test func `unread header on a new day appears after the day header`() {
        let messages = [
            makeMessage(id: 1, date: baseDate),
            makeMessage(id: 2, date: baseDate + twoDays),
        ]

        let items = ChatHistoryItem.makeItems(
            messages: messages,
            unreadMessageId: 2,
            unreadCount: 1,
            unreadHeaderVoiceOverFocusRequest: 0,
        )

        #expect(items.map(\.id) == [.day(1), .message(1), .day(2), .unread(2), .message(2)])
    }

    @Test func `unread id with no matching message adds no header`() {
        let messages = [makeMessage(id: 1, date: baseDate)]

        let items = ChatHistoryItem.makeItems(
            messages: messages,
            unreadMessageId: 999,
            unreadCount: 1,
            unreadHeaderVoiceOverFocusRequest: 0,
        )

        #expect(items.map(\.id) == [.day(1), .message(1)])
    }

    @Test func `messageId is nil for day and unread items and set for message items`() {
        let messages = [makeMessage(id: 1, date: baseDate), makeMessage(id: 2, date: baseDate + 60)]

        let items = ChatHistoryItem.makeItems(
            messages: messages,
            unreadMessageId: 2,
            unreadCount: 1,
            unreadHeaderVoiceOverFocusRequest: 0,
        )

        let byId = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        #expect(byId[.day(1)]?.messageId == nil)
        #expect(byId[.unread(2)]?.messageId == nil)
        #expect(byId[.message(1)]?.messageId == 1)
        #expect(byId[.message(2)]?.messageId == 2)
    }

    @Test func `content signature tracks neighbor identity, not just the message id`() {
        let first = makeMessage(id: 1, date: baseDate)
        let second = makeMessage(id: 2, date: baseDate + 60)

        let beforeInsertion = ChatHistoryItem.makeItems(
            messages: [first, second],
            unreadMessageId: nil,
            unreadCount: 0,
            unreadHeaderVoiceOverFocusRequest: 0,
        )

        let inserted = makeMessage(id: 3, date: baseDate + 30)
        let afterInsertion = ChatHistoryItem.makeItems(
            messages: [first, inserted, second],
            unreadMessageId: nil,
            unreadCount: 0,
            unreadHeaderVoiceOverFocusRequest: 0,
        )

        let firstSignatureBefore = beforeInsertion.first { $0.id == .message(1) }?.contentSignature
        let firstSignatureAfter = afterInsertion.first { $0.id == .message(1) }?.contentSignature

        // Same message object, but its `next` neighbor changed - the row must be told to
        // reconfigure (its grouping/tail rendering depends on the neighbor), not skipped.
        #expect(firstSignatureBefore != firstSignatureAfter)
    }

    @Test func `content signature is stable for identical objects and neighbors`() {
        let first = makeMessage(id: 1, date: baseDate)
        let second = makeMessage(id: 2, date: baseDate + 60)
        let messages = [first, second]

        let itemsA = ChatHistoryItem.makeItems(
            messages: messages,
            unreadMessageId: nil,
            unreadCount: 0,
            unreadHeaderVoiceOverFocusRequest: 0,
        )
        let itemsB = ChatHistoryItem.makeItems(
            messages: messages,
            unreadMessageId: nil,
            unreadCount: 0,
            unreadHeaderVoiceOverFocusRequest: 0,
        )

        #expect(itemsA.map(\.contentSignature) == itemsB.map(\.contentSignature))
    }

    @Test func `a replacement message instance with the same id changes the content signature`() {
        let original = makeMessage(id: 1, date: baseDate)
        let edited = makeMessage(id: 1, date: baseDate)

        let before = ChatHistoryItem(id: .message(1), kind: .message(original, previous: nil, next: nil))
        let after = ChatHistoryItem(id: .message(1), kind: .message(edited, previous: nil, next: nil))

        // Edits replace the `CustomMessage` instance while keeping `message.id` (and therefore the
        // row's identity) stable - the signature must still change so the cell gets reconfigured.
        #expect(before.id == after.id)
        #expect(before.contentSignature != after.contentSignature)
    }

    // MARK: Private

    private let baseDate = 1_700_000_000
    private let twoDays = 2 * 24 * 60 * 60

    private func makeMessage(id: Int64, date: Int) -> CustomMessage {
        CustomMessage(
            message: TDLibFixtures.message(id: id, chatId: 1, date: date),
            properties: .default,
        )
    }
}
