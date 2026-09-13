// ChatHistoryNavigatorTests.swift

@testable import BetterTG
import Testing

// MARK: - ChatHistoryNavigatorTests

@MainActor struct ChatHistoryNavigatorTests {
    @Test func `request remains pending until the target can perform it`() {
        let navigator = ChatHistoryNavigator()
        let target = ChatHistoryNavigationTarget()
        navigator.attach(target)

        navigator.scrollToBottom(animated: true)
        #expect(target.bottomRequests == [true])

        target.acceptsRequests = true
        navigator.flushPendingRequest()
        navigator.flushPendingRequest()
        #expect(target.bottomRequests == [true, true])
    }

    @Test func `new request replaces an older pending request`() {
        let navigator = ChatHistoryNavigator()
        let target = ChatHistoryNavigationTarget()
        navigator.attach(target)

        navigator.scrollToBottom(animated: true)
        navigator.scrollToMessage(42, anchor: .center, animated: false)
        target.acceptsRequests = true
        navigator.flushPendingRequest()

        #expect(target.bottomRequests == [true])
        #expect(target.messageRequests.map(\.id) == [42, 42])
    }

    @Test func `scrollToUnreadHeader submits an unread request`() {
        let navigator = ChatHistoryNavigator()
        let target = ChatHistoryNavigationTarget()
        navigator.attach(target)
        target.acceptsRequests = true

        navigator.scrollToUnreadHeader(startingAt: 7)

        #expect(target.unreadRequests == [7])
    }

    @Test func `detaching a stale target does not clear a newer attached target`() {
        let navigator = ChatHistoryNavigator()
        let old = ChatHistoryNavigationTarget()
        let current = ChatHistoryNavigationTarget()
        navigator.attach(old)
        navigator.attach(current)

        // Simulates `dismantleUIViewController` firing for a controller that SwiftUI already
        // replaced - it must not sever the navigator from the controller that took over.
        navigator.detach(old)

        current.acceptsRequests = true
        navigator.scrollToBottom(animated: true)

        #expect(current.bottomRequests == [true])
        #expect(old.bottomRequests.isEmpty)
    }

    @Test func `a request submitted with no attached target stays pending until one attaches`() {
        let navigator = ChatHistoryNavigator()

        navigator.scrollToBottom(animated: true)
        navigator.flushPendingRequest()

        let target = ChatHistoryNavigationTarget()
        target.acceptsRequests = true
        navigator.attach(target)

        #expect(target.bottomRequests == [true])
    }
}

// MARK: - ChatHistoryNavigationTarget

@MainActor private final class ChatHistoryNavigationTarget: ChatHistoryNavigating {
    struct MessageRequest {
        let id: Int64
    }

    var acceptsRequests = false
    var bottomRequests = [Bool]()
    var messageRequests = [MessageRequest]()
    var unreadRequests = [Int64]()

    func perform(_ request: ChatHistoryNavigator.Request) -> Bool {
        switch request {
        case .bottom(let animated):
            bottomRequests.append(animated)
        case .message(let id, _, _):
            messageRequests.append(MessageRequest(id: id))
        case .unread(let id):
            unreadRequests.append(id)
        }
        return acceptsRequests
    }
}
