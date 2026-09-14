// ChatOpeningCoordinator.swift

import Foundation
import Observation

/// Owns the one-time opening sequence. SwiftUI submits a plan once history is ready; UIKit
/// acknowledges positioning after appearance and layout. Only then may reading and focus start.
@MainActor @Observable final class ChatOpeningCoordinator {
    // MARK: Lifecycle

    init(schedule: @escaping (@escaping @MainActor @Sendable () -> Void) -> Void = { work in
        DispatchQueue.main.async(execute: work)
    }) {
        self.schedule = schedule
    }

    // MARK: Internal

    enum Phase {
        case waitingForHistory
        case positioning
        case ready
    }

    enum FocusTarget: Equatable {
        case none
        case composer
        case unreadHeader
        case message(Int64)
    }

    struct Plan {
        let scroll: ChatHistoryNavigator.Request
        let focus: FocusTarget
        let unreadMessageId: Int64?

        static func make(
            initialMessageId: Int64?,
            movesFocusToInitialMessage: Bool,
            unreadMessageId: Int64?,
            lastMessageId: Int64?,
            canCompose: Bool,
        ) -> Self {
            if let initialMessageId {
                return Self(
                    scroll: .message(initialMessageId, anchor: .center, animated: false),
                    focus: movesFocusToInitialMessage ? .message(initialMessageId) : .none,
                    unreadMessageId: unreadMessageId,
                )
            }
            if let unreadMessageId {
                return Self(scroll: .unread(unreadMessageId), focus: .unreadHeader, unreadMessageId: unreadMessageId)
            }
            return Self(
                scroll: .bottom(animated: false),
                focus: canCompose ? .composer : lastMessageId.map(FocusTarget.message) ?? .none,
                unreadMessageId: nil,
            )
        }
    }

    private(set) var phase = Phase.waitingForHistory
    private(set) var plan: Plan?
    private(set) var focusCancelled = false

    var isReady: Bool { phase == .ready }
    var focusTarget: FocusTarget { isReady && !focusCancelled ? plan?.focus ?? .none : .none }
    var composerFocusRequest: Int { focusTarget == .composer ? 1 : 0 }
    var unreadFocusRequest: Int { focusTarget == .unreadHeader ? 1 : 0 }

    func begin(plan: Plan, navigator: ChatHistoryNavigator, allowsFocus: Bool) {
        guard phase == .waitingForHistory else { return }
        // Keep the original unread anchor across pauses and later history insertions.
        if self.plan == nil {
            self.plan = plan
        }
        guard let plan = self.plan else { return }
        if !allowsFocus {
            focusCancelled = true
        }
        generation &+= 1
        let generation = generation
        phase = .positioning
        chatScrollTrace("opening: history ready, waiting for table positioning")
        navigator.positionInitially(plan.scroll) { [weak self] result in
            guard let self, self.generation == generation else { return }
            // Cross out of UIKit's current update/layout callback before changing observed state.
            schedule { [weak self] in
                guard let self, self.generation == generation, phase == .positioning else { return }
                switch result {
                case .positioned:
                    phase = .ready
                    chatScrollTrace("opening: table positioned, reading and focus enabled")
                case .superseded:
                    focusCancelled = true
                    phase = .ready
                    chatScrollTrace("opening: user navigation took over")
                case .cancelled:
                    focusCancelled = true
                    phase = .waitingForHistory
                    chatScrollTrace("opening: positioning cancelled")
                }
            }
        }
    }

    func cancelFocus() {
        focusCancelled = true
    }

    func leave(navigator: ChatHistoryNavigator) {
        generation &+= 1
        focusCancelled = true
        navigator.cancelInitialPositioning()
        if phase == .positioning {
            phase = .waitingForHistory
        }
    }

    // MARK: Private

    @ObservationIgnored private let schedule: (@escaping @MainActor @Sendable () -> Void) -> Void
    @ObservationIgnored private var generation = 0
}
