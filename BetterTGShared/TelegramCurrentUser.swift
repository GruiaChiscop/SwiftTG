// TelegramCurrentUser.swift

/// Caches the current account's user id so chat-list rows can skip showing an identity badge on
/// the user's own entry (mirrors Unigram's `user.Id != clientService.Options.MyId` check) and
/// detect the Saved Messages chat, without a `getMe()` round trip per row.
@MainActor final class TelegramCurrentUserCache {
    // MARK: Internal

    static let shared = TelegramCurrentUserCache()

    /// The already-resolved id, if any - `nil` until the first `userId(service:)` call completes.
    /// Callers that can't `await` (most chat-title/avatar render sites) read this directly instead;
    /// as long as resolution was triggered eagerly at session start, it's populated well before
    /// the chat list first renders.
    private(set) var userId: Int64?

    @discardableResult func userId(service: any TelegramService) async -> Int64? {
        if let userId {
            return userId
        }
        if let pendingTask {
            return await pendingTask.value
        }
        let task = Task<Int64?, Never> {
            await (try? service.getMe())?.id
        }
        pendingTask = task
        let resolved = await task.value
        userId = resolved
        pendingTask = nil
        return resolved
    }

    // MARK: Private

    private var pendingTask: Task<Int64?, Never>?
}
