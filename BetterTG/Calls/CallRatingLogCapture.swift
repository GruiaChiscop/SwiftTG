// CallRatingLogCapture.swift

import Foundation

/// Bridges tgcalls' asynchronous termination callback to the rating sheet. Every continuation is
/// stored under the lock and is removed before being resumed, so it can be completed exactly once.
final class CallRatingLogCapture: @unchecked Sendable {
    // MARK: Internal

    func begin(callId: Int) {
        let previous: State?
        lock.lock()
        previous = states.updateValue(.pending([]), forKey: callId)
        lock.unlock()
        dispose(previous)
    }

    func finish(callId: Int, url: URL?) {
        var waiters = [Waiter]()
        var unusedURL: URL?
        lock.lock()
        switch states[callId] {
        case .pending(let pendingWaiters):
            waiters = pendingWaiters
            states[callId] = .ready(url)
        case .ready(let previousURL):
            unusedURL = previousURL
            states[callId] = .ready(url)
        case nil:
            unusedURL = url
        }
        lock.unlock()

        removeFileIfNeeded(unusedURL, unlessMatching: url)
        for waiter in waiters {
            waiter.continuation.resume(returning: url)
        }
    }

    func url(callId: Int) async -> URL? {
        await withCheckedContinuation { continuation in
            let waiter = Waiter(id: UUID(), continuation: continuation)
            var needsTimeout = false
            lock.lock()
            switch states[callId] {
            case .pending(var waiters):
                waiters.append(waiter)
                states[callId] = .pending(waiters)
                needsTimeout = true
                lock.unlock()
            case .ready(let url):
                lock.unlock()
                continuation.resume(returning: url)
            case nil:
                lock.unlock()
                continuation.resume(returning: nil)
            }
            if needsTimeout {
                let waiterId = waiter.id
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.captureTimeout) { [weak self] in
                    self?.timeOut(waiterId: waiterId, callId: callId)
                }
            }
        }
    }

    func discard(callId: Int, fileDeletionDelay: TimeInterval = 0) {
        let previous: State?
        lock.lock()
        previous = states.removeValue(forKey: callId)
        lock.unlock()
        dispose(previous, fileDeletionDelay: fileDeletionDelay)
    }

    // MARK: Private

    private enum State {
        case pending([Waiter])
        case ready(URL?)
    }

    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<URL?, Never>
    }

    private static let captureTimeout: TimeInterval = 5

    private let lock = NSLock()
    private var states = [Int: State]()

    private func dispose(_ state: State?, fileDeletionDelay: TimeInterval = 0) {
        switch state {
        case .pending(let waiters):
            for waiter in waiters {
                waiter.continuation.resume(returning: nil)
            }
        case .ready(let url):
            removeFileIfNeeded(url, after: fileDeletionDelay)
        case nil:
            break
        }
    }

    private func removeFileIfNeeded(
        _ url: URL?,
        unlessMatching retainedURL: URL? = nil,
        after delay: TimeInterval = 0,
    ) {
        guard let url, url != retainedURL else { return }
        if delay > 0 {
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) {
                try? FileManager.default.removeItem(at: url)
            }
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func timeOut(waiterId: UUID, callId: Int) {
        var continuation: CheckedContinuation<URL?, Never>?
        lock.lock()
        if case .pending(var waiters) = states[callId],
           let index = waiters.firstIndex(where: { $0.id == waiterId })
        {
            continuation = waiters.remove(at: index).continuation
            states[callId] = .pending(waiters)
        }
        lock.unlock()
        continuation?.resume(returning: nil)
    }
}
