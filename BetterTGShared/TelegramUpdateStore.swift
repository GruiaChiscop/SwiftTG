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

    var availableMessageEffectsPublisher: AnyPublisher<UpdateAvailableMessageEffects?, Never> {
        availableMessageEffectsSubject.receive(on: DispatchQueue.main).eraseToAnyPublisher()
    }

    /// Same `CurrentValueSubject` reasoning as `chatFoldersPublisher` - TDLib pushes
    /// `updateReactionNotificationSettings` once early in the session with no matching getter, so a
    /// Notifications screen opened afterward needs the value replayed, not just future changes.
    var reactionNotificationSettingsPublisher: AnyPublisher<ReactionNotificationSettings?, Never> {
        reactionNotificationSettingsSubject.receive(on: DispatchQueue.main).eraseToAnyPublisher()
    }

    /// Same `CurrentValueSubject` reasoning as `chatFoldersPublisher` - a call screen presented
    /// after `updateCall` already fired (e.g. CallKit reporting the call before the in-app screen
    /// finishes appearing) still needs the call's current state, not just its next transition.
    var callPublisher: AnyPublisher<Call?, Never> {
        callSubject.receive(on: DispatchQueue.main).eraseToAnyPublisher()
    }

    /// `PassthroughSubject`, unlike `callPublisher` - signaling packets are one-shot events to feed
    /// into the call engine as they arrive, not state to replay to a subscriber that missed one.
    var callSignalingDataPublisher: AnyPublisher<UpdateNewCallSignalingData, Never> {
        callSignalingDataSubject.receive(on: DispatchQueue.main).eraseToAnyPublisher()
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
        queue.async {
            [
                updateSubject, chatFoldersSubject, unreadChatCountSubject, availableMessageEffectsSubject,
                reactionNotificationSettingsSubject, callSubject, callSignalingDataSubject,
            ] in
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
            if case .updateAvailableMessageEffects(let value) = update {
                availableMessageEffectsSubject.send(value)
            }
            if case .updateReactionNotificationSettings(let value) = update {
                reactionNotificationSettingsSubject.send(value.notificationSettings)
            }
            if case .updateCall(let value) = update {
                let isOngoing = switch value.call.state {
                case .callStateDiscarded, .callStateError: false
                default: true
                }
                callSubject.send(isOngoing ? value.call : nil)
            }
            if case .updateNewCallSignalingData(let value) = update {
                callSignalingDataSubject.send(value)
            }
            updateSubject.send(update)
        }
    }

    // MARK: Private

    private let chatFoldersSubject = CurrentValueSubject<UpdateChatFolders?, Never>(nil)
    private let unreadChatCountSubject = CurrentValueSubject<UpdateUnreadChatCount?, Never>(nil)
    private let availableMessageEffectsSubject = CurrentValueSubject<UpdateAvailableMessageEffects?, Never>(nil)
    private let reactionNotificationSettingsSubject = CurrentValueSubject<ReactionNotificationSettings?, Never>(nil)
    private let callSubject = CurrentValueSubject<Call?, Never>(nil)
    private let callSignalingDataSubject = PassthroughSubject<UpdateNewCallSignalingData, Never>()
    private let chatListStore = TelegramChatListStore()
    private let fileStore = TelegramFileStore()
    private let messageStore = TelegramMessageStore()
    private let queue = DispatchQueue(label: "com.gruiachiscop.BetterTG.telegram-updates")
    private let updateSubject = PassthroughSubject<Update, Never>()
}
