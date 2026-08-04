// TelegramCurrentUser.swift

/// Caches the current account's user id so chat-list rows can skip showing an identity badge on
/// the user's own entry (mirrors Unigram's `user.Id != clientService.Options.MyId` check),
/// without a `getMe()` round trip per row.
@MainActor final class TelegramCurrentUserCache {
    // MARK: Internal

    static let shared = TelegramCurrentUserCache()

    func userId(service: any TelegramService) async -> Int64? {
        if let cachedUserId {
            return cachedUserId
        }
        if let pendingTask {
            return await pendingTask.value
        }
        let task = Task<Int64?, Never> {
            await (try? service.getMe())?.id
        }
        pendingTask = task
        let resolved = await task.value
        cachedUserId = resolved
        pendingTask = nil
        return resolved
    }

    // MARK: Private

    private var cachedUserId: Int64?
    private var pendingTask: Task<Int64?, Never>?
}
