// TelegramSearchPolicyTests.swift

@testable import BetterTG
import TDLibKit
import Testing

struct TelegramSearchPolicyTests {
    @Test func `main and archive message searches retain their chat-list scope`() {
        #expect(TelegramSearchPolicy.messageChatListScope(for: .chatListMain) == .chatListMain)
        #expect(TelegramSearchPolicy.messageChatListScope(for: .chatListArchive) == .chatListArchive)
    }

    @Test func `custom folder message search uses the supported all-chats scope`() {
        let folder = ChatList.chatListFolder(.init(chatFolderId: 42))

        #expect(TelegramSearchPolicy.messageChatListScope(for: folder) == nil)
    }
}
