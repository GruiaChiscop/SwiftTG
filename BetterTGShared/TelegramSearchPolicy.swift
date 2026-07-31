// TelegramSearchPolicy.swift

enum TelegramSearchPolicy {
    static let globalQueryDebounce: Duration = .milliseconds(300)
    static let conversationQueryDebounce: Duration = .milliseconds(250)
}
