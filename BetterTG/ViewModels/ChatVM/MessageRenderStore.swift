// MessageRenderStore.swift

import TDLibKit

// MARK: - MessageRenderState

/// Per-message bookkeeping for ChatVM's render pipeline. Raw TDLib `Message` values are
/// intentionally not retained here: copying or comparing them recursively is expensive for
/// media-heavy channel history.
struct MessageRenderState: Equatable {
    /// The invalidation version this message should be rendered at. Bumped whenever content may
    /// have changed in a way the raw `Message` equality check alone won't catch (edit, pin
    /// change) — the render/refresh machinery chases this number.
    var invalidationVersion: UInt64 = 0

    /// The invalidation version satisfied by the last completed render.
    var renderedVersion: UInt64?

    /// The invalidation version of the render currently in flight, if any.
    var renderingVersion: UInt64?
    /// Monotonic id for the in-flight render, used to discard a stale completion if a newer
    /// render for the same message id started before this one finished.
    var renderGeneration: UInt64 = 0

    /// The version of the in-flight "refetch this message" request, if any. While set, reconcile
    /// won't start a new render — the refetch will feed the store an updated snapshot instead.
    var refreshVersion: UInt64?
    /// Whether a refetched message was staged until the shared snapshot reflects the merge.
    var isRefreshedMessageAwaitingMerge = false
}

// MARK: - MessageRenderStore

/// Pure state machine behind ChatVM's message-render pipeline. Holds no service reference and
/// starts no async work itself — ChatVM drives it and performs the TDLib calls its decisions
/// call for.
struct MessageRenderStore {
    private(set) var states = [Int64: MessageRenderState]()
    private var nextRenderGeneration: UInt64 = 0

    /// Drops bookkeeping for ids no longer present in the chat, then returns the messages that
    /// need a new render started now, each with the invalidation version it should be rendered
    /// at.
    mutating func reconcile(
        currentIds: Set<Int64>,
        messages: [Int64: Message],
    ) -> [(message: Message, invalidationVersion: UInt64)] {
        states = states.filter { currentIds.contains($0.key) }

        var toRender = [(message: Message, invalidationVersion: UInt64)]()
        for id in currentIds {
            guard let message = messages[id] else { continue }
            let state = states[id] ?? MessageRenderState()
            let invalidationVersion = state.invalidationVersion
            let outOfDate = state.renderedVersion == nil || (state.renderedVersion ?? 0) < invalidationVersion
            guard outOfDate else { continue }
            guard state.refreshVersion == nil else { continue }
            if state.renderingVersion == invalidationVersion {
                continue
            }
            toRender.append((message, invalidationVersion))
        }
        return toRender
    }

    /// Marks a render as started for `message`, returning the generation to check for staleness
    /// when the async work completes.
    @discardableResult
    mutating func beginRendering(_ message: Message, invalidationVersion: UInt64) -> UInt64 {
        nextRenderGeneration += 1
        let generation = nextRenderGeneration
        var state = states[message.id] ?? MessageRenderState()
        state.renderGeneration = generation
        state.renderingVersion = invalidationVersion
        states[message.id] = state
        return generation
    }

    /// Whether a completed render for `messageId` is still current and should be committed.
    /// `currentMessage` must still exist under this id. Content changes increment the store's
    /// invalidation version before a new render is accepted.
    func isRenderStillCurrent(
        messageId: Int64,
        generation: UInt64,
        invalidationVersion: UInt64,
        currentMessage: Message?,
    ) -> Bool {
        guard let state = states[messageId] else { return false }
        return state.renderGeneration == generation
            && state.renderingVersion == invalidationVersion
            && currentMessage?.id == messageId
            && state.invalidationVersion == invalidationVersion
    }

    /// Commits a completed render: clears the in-flight bookkeeping and records the result.
    mutating func commitRender(messageId: Int64, message: Message, invalidationVersion: UInt64) {
        var state = states[messageId] ?? MessageRenderState()
        state.renderingVersion = nil
        state.renderedVersion = invalidationVersion
        states[messageId] = state
    }

    /// Bumps the invalidation version for `messageId` so the next reconcile re-renders it.
    mutating func invalidate(messageId: Int64, version: UInt64) {
        states[messageId, default: MessageRenderState()].invalidationVersion = version
    }

    /// Starts tracking a refetch for `messageId` at `version`. While tracked, reconcile skips
    /// starting a fresh render for this id.
    mutating func beginRefresh(messageId: Int64, version: UInt64) {
        var state = states[messageId] ?? MessageRenderState()
        state.refreshVersion = version
        state.isRefreshedMessageAwaitingMerge = false
        states[messageId] = state
    }

    /// Whether a refresh started for `messageId` at `version` is still the current one (hasn't
    /// been superseded by a newer refresh).
    func isRefreshStillCurrent(messageId: Int64, version: UInt64) -> Bool {
        states[messageId]?.refreshVersion == version
    }

    /// Clears refresh tracking after a failed refetch, allowing a future render attempt.
    mutating func cancelRefresh(messageId: Int64) {
        states[messageId]?.refreshVersion = nil
        states[messageId]?.invalidationVersion = 0
    }

    /// Stages a successfully refetched message, to be merged back into the shared store by the
    /// caller.
    mutating func stageRefreshedMessage(_ message: Message, for messageId: Int64) {
        guard message.id == messageId else { return }
        states[messageId]?.isRefreshedMessageAwaitingMerge = true
    }

    /// Clears refresh tracking for any id whose staged refresh now matches the live snapshot,
    /// meaning the merge completed.
    mutating func completeRefreshesIfMerged(messages: [Int64: Message]) {
        for (messageId, state) in states {
            guard state.isRefreshedMessageAwaitingMerge, messages[messageId] != nil else { continue }
            states[messageId]?.isRefreshedMessageAwaitingMerge = false
            states[messageId]?.refreshVersion = nil
        }
    }
}
