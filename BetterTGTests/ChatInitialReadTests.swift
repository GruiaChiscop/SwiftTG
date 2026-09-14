// ChatInitialReadTests.swift

@testable import BetterTG
import TDLibKit
import Testing

@MainActor struct ChatInitialReadTests {
    // MARK: Internal

    @Test func `opening marks through the entry last message even when it is not visible`() async {
        let service = FakeTelegramService()
        let vm = makeVM(service: service)
        vm.initialMessagesLoaded = true
        vm.markInitialMessagesRead()
        vm.markInitialMessagesRead()
        await vm.initialReadTask?.value
        let requests = service.viewedMessages.withLock { $0 }
        #expect(requests.count == 1)
        #expect(requests.first?.ids == [200])
        #expect(requests.first?.forceRead == true)
        #expect(vm.initialUnreadCount == 159)
    }

    @Test func `read boundary stays at entry snapshot when a new message arrives`() async {
        let service = FakeTelegramService()
        let vm = makeVM(service: service)
        vm.customChat.lastMessage = TDLibFixtures.message(id: 300, chatId: 1, date: 100, text: "New arrival")
        vm.initialMessagesLoaded = true
        vm.markInitialMessagesRead()
        await vm.initialReadTask?.value
        #expect(service.viewedMessages.withLock { $0.first?.ids } == [200])
    }

    @Test func `loading and message deep links do not mark the whole chat read`() {
        let service = FakeTelegramService()
        let loading = makeVM(service: service)
        loading.markInitialMessagesRead()
        #expect(loading.initialReadTask == nil)
        let deepLink = makeVM(service: service, initialMessageId: 50)
        deepLink.initialMessagesLoaded = true
        deepLink.markInitialMessagesRead()
        #expect(deepLink.initialReadTask == nil)
    }

    @Test func `cached merged history cannot complete initial loading before a fresh fetch`() {
        let vm = makeVM(service: FakeTelegramService())
        vm.conversationPrepared = true
        vm.handle(mergedSnapshot(version: 1))
        #expect(!vm.initialMessagesLoaded)
        vm.hasLoadedInitialHistory = true
        vm.handle(mergedSnapshot(version: 2))
        #expect(vm.initialMessagesLoaded)
    }

    @Test func `initial loading waits for the fetched ids to reach the message snapshot`() {
        let vm = makeVM(service: FakeTelegramService())
        vm.conversationPrepared = true
        vm.hasLoadedInitialHistory = true
        vm.loadedMessageIds = [200]
        vm.handle(mergedSnapshot(version: 1))
        #expect(!vm.initialMessagesLoaded)
    }

    @Test func `cached rows do not turn initial fetch into an older history page`() async {
        let service = FakeTelegramService()
        let vm = makeVM(service: service)
        vm.loadedMessageIds = [50]
        vm.messages = [CustomMessage(
            message: TDLibFixtures.message(id: 50, chatId: 1, date: 100, text: "Cached"),
            properties: .default,
        )]
        vm.loadMessages()
        await vm.loadingMessagesTask?.value
        #expect(service.historyRequests.withLock { $0.first?.fromMessageId } == 0)
        #expect(service.historyRequests.withLock { $0.first?.limit } == ChatVM.initialHistoryWindowSize)
    }

    // MARK: Private

    private func makeVM(service: FakeTelegramService, initialMessageId: Int64? = nil) -> ChatVM {
        let last = TDLibFixtures.message(id: 200, chatId: 1, date: 100, text: "Latest")
        let chat = TDLibFixtures.chat(id: 1, order: 1, unreadCount: 159, lastMessage: last)
        return ChatVM(
            customChat: CustomChat(
                chat: chat,
                position: TDLibFixtures.position(order: 1),
                unreadCount: 159,
                type: .user(TDLibFixtures.user(id: 1)),
            ),
            initialMessageId: initialMessageId,
            service: service,
        )
    }

    private func mergedSnapshot(version: UInt64) -> TelegramMessageSnapshot {
        TelegramMessageSnapshot(
            chatId: 1,
            version: version,
            messages: [:],
            orderedMessageIds: [],
            unreadCount: 159,
            hasMergedHistory: true,
            change: .historyMerged,
        )
    }
}
