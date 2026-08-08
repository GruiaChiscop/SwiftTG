// TelegramUpdateStore.swift

@preconcurrency import Combine
import Foundation
@preconcurrency import TDLibKit

final class TelegramUpdateStore: @unchecked Sendable {
    // MARK: Internal

    var chatListPublisher: AnyPublisher<ChatListSnapshot, Never> {
        chatListStore.publisher
    }

    /// Delivered on the main thread - `updateSubject` is written from `queue` (this store's
    /// private background queue), but every consumer is a SwiftUI `.onReceive`/`@Observable`
    /// update, which requires the main thread.
    var updatePublisher: AnyPublisher<Update, Never> {
        updateSubject.receive(on: DispatchQueue.main).eraseToAnyPublisher()
    }

    var authorizationStatePublisher: AnyPublisher<AuthorizationState, Never> {
        updateSubject
            .compactMap { update in
                guard case .updateAuthorizationState(let value) = update else { return nil }
                return value.authorizationState
            }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    /// `CurrentValueSubject`, not a plain filter over `updatePublisher` - TDLib pushes
    /// `updateChatFolders` once, early in the session, and won't repeat it just because a new
    /// screen subscribes later. A `PassthroughSubject`-backed filter would leave a Settings screen
    /// opened after that point stuck showing an empty folder list until the user's folders actually
    /// change again. `CurrentValueSubject` replays its latest value to every new subscriber instead.
    var chatFoldersPublisher: AnyPublisher<UpdateChatFolders?, Never> {
        chatFoldersSubject.receive(on: DispatchQueue.main).eraseToAnyPublisher()
    }

    /// Same `CurrentValueSubject` reasoning as `chatFoldersPublisher` - the app-icon/Dock badge
    /// subscriber is wired up once at launch, and needs the count TDLib already knows about even
    /// if `updateUnreadChatCount` for `.chatListMain` last fired before that subscription existed.
    var unreadChatCountPublisher: AnyPublisher<UpdateUnreadChatCount?, Never> {
        unreadChatCountSubject.receive(on: DispatchQueue.main).eraseToAnyPublisher()
    }

    func messagePublisher(chatId: Int64) -> AnyPublisher<TelegramMessageSnapshot, Never> {
        messageStore.publisher(chatId: chatId)
    }

    func filePublisher(fileId: Int) -> AnyPublisher<File, Never> {
        fileStore.publisher(fileId: fileId)
    }

    func mergeMessageHistory(chatId: Int64, messages: [Message]) {
        messageStore.mergeHistory(chatId: chatId, messages: messages)
    }

    func replaceMessageHistory(chatId: Int64, messages: [Message]) {
        messageStore.replaceHistory(chatId: chatId, messages: messages)
    }

    func mergeMessages(chatId: Int64, messages: [Message]) {
        messageStore.mergeMessages(chatId: chatId, messages: messages)
    }

    func mergeChatListChats(_ chats: [Chat]) {
        queue.async {
            dispatchPrecondition(condition: .onQueue(self.queue))
            self.chatListStore.mergeChats(chats)
        }
    }

    func mergeInitialFile(_ file: File) {
        fileStore.mergeInitial(file)
    }

    func publish(_ update: Update) {
        queue.async { [updateSubject, chatFoldersSubject, unreadChatCountSubject] in
            dispatchPrecondition(condition: .onQueue(self.queue))
            self.chatListStore.reduce(update)
            self.fileStore.reduce(update)
            self.messageStore.reduce(update)
            if case .updateChatFolders(let value) = update {
                chatFoldersSubject.send(value)
            }
            if case .updateUnreadChatCount(let value) = update, value.chatList == .chatListMain {
                unreadChatCountSubject.send(value)
            }
            updateSubject.send(update)
        }
    }

    // MARK: Private

    private let chatFoldersSubject = CurrentValueSubject<UpdateChatFolders?, Never>(nil)
    private let unreadChatCountSubject = CurrentValueSubject<UpdateUnreadChatCount?, Never>(nil)
    private let chatListStore = TelegramChatListStore()
    private let fileStore = TelegramFileStore()
    private let messageStore = TelegramMessageStore()
    private let queue = DispatchQueue(label: "com.gruiachiscop.BetterTG.telegram-updates")
    private let updateSubject = PassthroughSubject<Update, Never>()
}
