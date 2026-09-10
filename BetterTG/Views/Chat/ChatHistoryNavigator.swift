// ChatHistoryNavigator.swift

import SwiftUI

// MARK: - ChatHistoryNavigating

@MainActor protocol ChatHistoryNavigating: AnyObject {
    func perform(_ request: ChatHistoryNavigator.Request) -> Bool
}

// MARK: - ChatHistoryNavigator

/// Stable bridge between SwiftUI/ChatVM commands and the currently mounted collection view.
/// Requests remain pending while their row has not arrived yet, which also covers navigation that
/// first has to fetch a history window around a message.
@MainActor final class ChatHistoryNavigator {
    // MARK: Internal

    enum Anchor {
        case bottom
        case center
        case top

        // MARK: Lifecycle

        init(_ unitPoint: UnitPoint) {
            self =
                if unitPoint == .top {
                    .top
                } else if unitPoint == .bottom {
                    .bottom
                } else {
                    .center
                }
        }
    }

    enum Request {
        case bottom(animated: Bool)
        case message(Int64, anchor: Anchor, animated: Bool)
        case unread(Int64)
    }

    func attach(_ target: any ChatHistoryNavigating) {
        self.target = target
        flushPendingRequest()
    }

    func detach(_ target: any ChatHistoryNavigating) {
        guard self.target === target else { return }
        self.target = nil
    }

    func scrollToBottom(animated: Bool) {
        submit(.bottom(animated: animated))
    }

    func scrollToMessage(_ messageId: Int64, anchor: Anchor, animated: Bool) {
        submit(.message(messageId, anchor: anchor, animated: animated))
    }

    func scrollToUnreadHeader(startingAt messageId: Int64) {
        submit(.unread(messageId))
    }

    func flushPendingRequest() {
        guard let pendingRequest, target?.perform(pendingRequest) == true else { return }
        self.pendingRequest = nil
    }

    // MARK: Private

    private weak var target: (any ChatHistoryNavigating)?
    private var pendingRequest: Request?

    private func submit(_ request: Request) {
        pendingRequest =
            if target?.perform(request) == true {
                nil
            } else {
                request
            }
    }
}
