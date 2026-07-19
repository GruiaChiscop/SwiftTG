// MessageRenderStoreTests.swift

@testable import BetterTG
import TDLibKit
import Testing

struct MessageRenderStoreTests {
    @Test func `a new message needs rendering`() {
        var store = MessageRenderStore()
        let message = TDLibFixtures.message(id: 1, chatId: 1, date: 100)

        let toRender = store.reconcile(currentIds: [message.id], messages: [message.id: message])

        #expect(toRender.map(\.message.id) == [message.id])
    }

    @Test func `a committed render is not requested again for the same content`() {
        var store = MessageRenderStore()
        let message = TDLibFixtures.message(id: 1, chatId: 1, date: 100)

        store.commitRender(messageId: message.id, message: message, invalidationVersion: 0)
        let toRender = store.reconcile(currentIds: [message.id], messages: [message.id: message])

        #expect(toRender.isEmpty)
    }

    @Test func `changed content relies on the snapshot change invalidation`() {
        var store = MessageRenderStore()
        let original = TDLibFixtures.message(id: 1, chatId: 1, date: 100, text: "Original")
        let edited = TDLibFixtures.message(id: 1, chatId: 1, date: 100, text: "Edited")

        store.commitRender(messageId: original.id, message: original, invalidationVersion: 0)
        let toRender = store.reconcile(currentIds: [original.id], messages: [original.id: edited])

        #expect(toRender.isEmpty)
    }

    @Test func `invalidate forces a re-render of unchanged content`() {
        var store = MessageRenderStore()
        let message = TDLibFixtures.message(id: 1, chatId: 1, date: 100)

        store.commitRender(messageId: message.id, message: message, invalidationVersion: 0)
        store.invalidate(messageId: message.id, version: 1)
        let toRender = store.reconcile(currentIds: [message.id], messages: [message.id: message])

        #expect(toRender.map(\.invalidationVersion) == [1])
    }

    @Test func `a render already in flight for the same content is not duplicated`() {
        var store = MessageRenderStore()
        let message = TDLibFixtures.message(id: 1, chatId: 1, date: 100)

        store.beginRendering(message, invalidationVersion: 0)
        let toRender = store.reconcile(currentIds: [message.id], messages: [message.id: message])

        #expect(toRender.isEmpty)
    }

    @Test func `an in-flight render is superseded after invalidation`() {
        var store = MessageRenderStore()
        let original = TDLibFixtures.message(id: 1, chatId: 1, date: 100, text: "Original")
        let edited = TDLibFixtures.message(id: 1, chatId: 1, date: 100, text: "Edited")

        store.beginRendering(original, invalidationVersion: 0)
        store.invalidate(messageId: original.id, version: 1)
        let toRender = store.reconcile(currentIds: [original.id], messages: [original.id: edited])

        #expect(toRender.map(\.message.id) == [original.id])
    }

    @Test func `a completion is current only when generation, version, and content all match`() {
        var store = MessageRenderStore()
        let message = TDLibFixtures.message(id: 1, chatId: 1, date: 100)
        let generation = store.beginRendering(message, invalidationVersion: 0)

        #expect(store.isRenderStillCurrent(
            messageId: message.id, generation: generation, invalidationVersion: 0, currentMessage: message,
        ))
        #expect(!store.isRenderStillCurrent(
            messageId: message.id, generation: generation + 1, invalidationVersion: 0, currentMessage: message,
        ))
        #expect(!store.isRenderStillCurrent(
            messageId: message.id, generation: generation, invalidationVersion: 1, currentMessage: message,
        ))
        #expect(!store.isRenderStillCurrent(
            messageId: message.id, generation: generation, invalidationVersion: 0, currentMessage: nil,
        ))
    }

    @Test func `a completion is stale once a newer render for the same message started`() {
        var store = MessageRenderStore()
        let message = TDLibFixtures.message(id: 1, chatId: 1, date: 100)
        let firstGeneration = store.beginRendering(message, invalidationVersion: 0)
        store.invalidate(messageId: message.id, version: 1)
        store.beginRendering(message, invalidationVersion: 1)

        #expect(!store.isRenderStillCurrent(
            messageId: message.id, generation: firstGeneration, invalidationVersion: 0, currentMessage: message,
        ))
    }

    @Test func `a pending refresh blocks a fresh render even for changed content`() {
        var store = MessageRenderStore()
        let original = TDLibFixtures.message(id: 1, chatId: 1, date: 100, text: "Original")
        let edited = TDLibFixtures.message(id: 1, chatId: 1, date: 100, text: "Edited")

        store.commitRender(messageId: original.id, message: original, invalidationVersion: 0)
        store.beginRefresh(messageId: original.id, version: 1)
        let toRender = store.reconcile(currentIds: [original.id], messages: [original.id: edited])

        #expect(toRender.isEmpty)
    }

    @Test func `a failed refresh clears tracking so a future render can proceed`() {
        var store = MessageRenderStore()
        let message = TDLibFixtures.message(id: 1, chatId: 1, date: 100)

        store.beginRefresh(messageId: message.id, version: 1)
        store.cancelRefresh(messageId: message.id)

        #expect(!store.isRefreshStillCurrent(messageId: message.id, version: 1))
        let toRender = store.reconcile(currentIds: [message.id], messages: [message.id: message])
        #expect(toRender.map(\.message.id) == [message.id])
    }

    @Test func `a confirmed message is rendered independently from its temporary id`() {
        var store = MessageRenderStore()
        let temporary = TDLibFixtures.message(id: -1, chatId: 1, date: 100)
        let confirmed = TDLibFixtures.message(id: 10, chatId: 1, date: 100)

        store.commitRender(messageId: temporary.id, message: temporary, invalidationVersion: 0)
        store.invalidate(messageId: confirmed.id, version: 5)

        let toRender = store.reconcile(currentIds: [confirmed.id], messages: [confirmed.id: confirmed])
        #expect(toRender.map(\.message.id) == [confirmed.id])
        #expect(toRender.first?.invalidationVersion == 5)
    }

    @Test func `a merged refresh clears its own tracking without touching other messages`() {
        var store = MessageRenderStore()
        let refreshed = TDLibFixtures.message(id: 1, chatId: 1, date: 100, text: "Edited")
        let other = TDLibFixtures.message(id: 2, chatId: 1, date: 100)

        store.beginRefresh(messageId: refreshed.id, version: 1)
        store.stageRefreshedMessage(refreshed, for: refreshed.id)
        store.beginRefresh(messageId: other.id, version: 1)
        store.stageRefreshedMessage(other, for: other.id)

        store.completeRefreshesIfMerged(messages: [refreshed.id: refreshed])

        #expect(!store.isRefreshStillCurrent(messageId: refreshed.id, version: 1))
        #expect(store.isRefreshStillCurrent(messageId: other.id, version: 1))
    }

    @Test func `reconcile drops bookkeeping for messages no longer in the chat`() {
        var store = MessageRenderStore()
        let message = TDLibFixtures.message(id: 1, chatId: 1, date: 100)

        store.commitRender(messageId: message.id, message: message, invalidationVersion: 0)
        _ = store.reconcile(currentIds: [], messages: [:])

        #expect(store.states[message.id] == nil)
    }
}
