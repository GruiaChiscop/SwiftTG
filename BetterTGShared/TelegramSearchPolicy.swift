// TelegramSearchPolicy.swift

import TDLibKit

enum TelegramSearchPolicy {
    static let globalQueryDebounce = Duration.milliseconds(300)
    static let conversationQueryDebounce = Duration.milliseconds(250)

    /// TDLib can scope global message search to the main list or archive. Custom folders aren't
    /// accepted as a server-side message-search scope, so they retain Telegram's all-chats search.
    static func messageChatListScope(for chatList: ChatList) -> ChatList? {
        switch chatList {
        case .chatListArchive, .chatListMain:
            chatList
        case .chatListFolder:
            nil
        }
    }
}
