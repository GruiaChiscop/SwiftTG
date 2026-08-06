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
        queue.async { [updateSubject] in
            dispatchPrecondition(condition: .onQueue(self.queue))
            self.chatListStore.reduce(update)
            self.fileStore.reduce(update)
            self.messageStore.reduce(update)
            updateSubject.send(update)
        }
    }

    // MARK: Private

    private let chatListStore = TelegramChatListStore()
    private let fileStore = TelegramFileStore()
    private let messageStore = TelegramMessageStore()
    private let queue = DispatchQueue(label: "com.gruiachiscop.BetterTG.telegram-updates")
    private let updateSubject = PassthroughSubject<Update, Never>()
}
