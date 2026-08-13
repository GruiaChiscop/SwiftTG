// CallContextQueue.swift

import Foundation
import TgVoipWebrtc

/// tgcalls dispatches its own internal work (signaling, media, teardown) through this queue rather
/// than assuming a particular threading model - `OngoingCallThreadLocalContextWebrtc` is documented
/// as not thread-safe outside of it. A dedicated serial `DispatchQueue` (not the main queue) keeps
/// the engine's own work off the UI thread.
final class CallContextQueue: NSObject, OngoingCallThreadLocalContextQueueWebrtc {
    // MARK: Lifecycle

    init(queue: DispatchQueue) {
        self.queue = queue
        super.init()
        queue.setSpecific(key: Self.key, value: ())
    }

    // MARK: Internal

    func dispatch(_ f: @escaping () -> Void) {
        queue.async(execute: f)
    }

    func isCurrent() -> Bool {
        DispatchQueue.getSpecific(key: Self.key) != nil
    }

    func scheduleBlock(_ f: @escaping () -> Void, after timeout: Double) -> GroupCallDisposable {
        let item = DispatchWorkItem(block: f)
        queue.asyncAfter(deadline: .now() + timeout, execute: item)
        return GroupCallDisposable { item.cancel() }
    }

    // MARK: Private

    private static let key = DispatchSpecificKey<Void>()
    private let queue: DispatchQueue
}
