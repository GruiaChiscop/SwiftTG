// ChatHistoryNavigator.swift

import SwiftUI

// MARK: - ChatHistoryNavigating

@MainActor protocol ChatHistoryNavigating: AnyObject {
    func perform(_ request: ChatHistoryNavigator.Request) -> Bool
    func performInitial(_ request: ChatHistoryNavigator.Request) -> Bool
}

// MARK: - ChatHistoryNavigator

/// Stable bridge between SwiftUI/ChatVM commands and the currently mounted history table.
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

    enum InitialPositioningResult {
        case positioned
        case superseded
        case cancelled
    }

    var hasPendingRequest: Bool { pendingRequest != nil }
    var hasPendingInitialPosition: Bool { pendingRequest != nil && initialCompletion != nil }

    func positionInitially(_ request: Request, completion: @escaping (InitialPositioningResult) -> Void) {
        cancelInitialPositioning()
        requestGeneration &+= 1
        pendingRequest = request
        initialCompletion = completion
        flushPendingRequest()
    }

    func cancelInitialPositioning() {
        guard let completion = initialCompletion else { return }
        requestGeneration &+= 1
        pendingRequest = nil
        initialCompletion = nil
        completion(.cancelled)
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
        guard !isPerformingRequest, let pendingRequest else { return }
        isPerformingRequest = true
        let generation = requestGeneration
        defer { isPerformingRequest = false }
        let completed = initialCompletion == nil
            ? target?.perform(pendingRequest)
            : target?.performInitial(pendingRequest)
        if completed == true, generation == requestGeneration {
            self.pendingRequest = nil
            let completion = initialCompletion
            initialCompletion = nil
            completion?(.positioned)
        }
    }

    // MARK: Private

    private weak var target: (any ChatHistoryNavigating)?
    private var pendingRequest: Request?
    private var initialCompletion: ((InitialPositioningResult) -> Void)?
    private var isPerformingRequest = false
    private var requestGeneration = 0

    private func submit(_ request: Request) {
        let superseded = initialCompletion
        initialCompletion = nil
        requestGeneration &+= 1
        pendingRequest = request
        superseded?(.superseded)
        flushPendingRequest()
    }
}
