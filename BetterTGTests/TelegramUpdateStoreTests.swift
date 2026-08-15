// TelegramUpdateStoreTests.swift

@testable import BetterTG
import Combine
import Foundation
import TDLibKit
import Testing

struct TelegramUpdateStoreTests {
    // MARK: Internal

    @Test func `call is published and replayed to a subscriber`() throws {
        let store = TelegramUpdateStore()
        let call = TDLibFixtures.call(id: 1)
        store.publish(.updateCall(.init(call: call)))

        let received = try waitForCall(store: store) { $0 == call }
        #expect(received == call)

        let replayed = try waitForCall(store: store) { $0 == call }
        #expect(replayed == call)
    }

    @Test func `discarded call is published with its discard reason intact`() throws {
        let store = TelegramUpdateStore()
        let ready = TDLibFixtures.call(id: 2)
        store.publish(.updateCall(.init(call: ready)))
        _ = try waitForCall(store: store) { $0 == ready }

        let discarded = TDLibFixtures.call(
            id: 2,
            state: .callStateDiscarded(.init(
                needDebugInformation: false,
                needLog: false,
                needRating: false,
                reason: .callDiscardReasonHungUp,
            )),
        )
        store.publish(.updateCall(.init(call: discarded)))

        // The store must deliver the terminal call as-is, not collapse it to nil - callers need the
        // real state to know (and log) why a call ended, not just that it did.
        let replayed = try waitForCall(store: store) { $0 == discarded }
        #expect(replayed == discarded)
    }

    @Test func `call ended with an error is published with its error intact`() throws {
        let store = TelegramUpdateStore()
        let ready = TDLibFixtures.call(id: 3)
        store.publish(.updateCall(.init(call: ready)))
        _ = try waitForCall(store: store) { $0 == ready }

        let errored = TDLibFixtures.call(
            id: 3,
            state: .callStateError(.init(error: .init(code: 4_005_000, message: "timeout"))),
        )
        store.publish(.updateCall(.init(call: errored)))

        let replayed = try waitForCall(store: store) { $0 == errored }
        #expect(replayed == errored)
    }

    @Test func `signaling data is delivered as a one-shot event`() {
        let store = TelegramUpdateStore()
        let payload = UpdateNewCallSignalingData(callId: 5, data: Data([1, 2, 3]))

        let semaphore = DispatchSemaphore(value: 0)
        var received: UpdateNewCallSignalingData?
        let cancellable = store.callSignalingDataPublisher.sink { value in
            received = value
            semaphore.signal()
        }

        store.publish(.updateNewCallSignalingData(payload))

        let waitResult = semaphore.wait(timeout: .now() + 2)
        withExtendedLifetime(cancellable) {}
        #expect(waitResult == .success)
        #expect(received == payload)
    }

    // MARK: Private

    private func waitForCall(
        store: TelegramUpdateStore,
        matching predicate: @escaping (Call?) -> Bool,
    ) -> Call? {
        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var result: Call?
        var didSignal = false
        let cancellable = store.callPublisher.sink { call in
            lock.lock()
            defer { lock.unlock() }
            guard !didSignal, predicate(call) else { return }
            didSignal = true
            result = call
            semaphore.signal()
        }

        let waitResult = semaphore.wait(timeout: .now() + 2)
        withExtendedLifetime(cancellable) {}
        #expect(waitResult == .success)
        return result
    }
}
