// TelegramSession.swift

import Combine
import Foundation
import TDLibKit

// MARK: - TelegramSessionConfiguration

struct TelegramSessionConfiguration: Sendable {
    let apiHash: String
    let apiId: Int
    let applicationVersion: String
    let databaseDirectory: String
    let deviceModel: String
    let systemLanguageCode: String
    let systemVersion: String
}

// MARK: - TelegramSession

final class TelegramSession: @unchecked Sendable {
    // MARK: Lifecycle

    init() {
        _ = internalClient
    }

    // MARK: Internal

    var client: TDLibClient { internalClient }

    var authorizationStatePublisher: AnyPublisher<AuthorizationState, Never> {
        updateStore.authorizationStatePublisher
    }

    var chatListPublisher: AnyPublisher<ChatListSnapshot, Never> {
        updateStore.chatListPublisher
    }

    var chatFoldersPublisher: AnyPublisher<UpdateChatFolders?, Never> {
        updateStore.chatFoldersPublisher
    }

    var unreadChatCountPublisher: AnyPublisher<UpdateUnreadChatCount?, Never> {
        updateStore.unreadChatCountPublisher
    }

    var availableMessageEffectsPublisher: AnyPublisher<UpdateAvailableMessageEffects?, Never> {
        updateStore.availableMessageEffectsPublisher
    }

    var reactionNotificationSettingsPublisher: AnyPublisher<ReactionNotificationSettings?, Never> {
        updateStore.reactionNotificationSettingsPublisher
    }

    var updatePublisher: AnyPublisher<Update, Never> {
        updateStore.updatePublisher
    }

    var callPublisher: AnyPublisher<Call?, Never> {
        updateStore.callPublisher
    }

    var callSignalingDataPublisher: AnyPublisher<UpdateNewCallSignalingData, Never> {
        updateStore.callSignalingDataPublisher
    }

    func filePublisher(fileId: Int) -> AnyPublisher<File, Never> {
        updateStore.filePublisher(fileId: fileId)
    }

    func messagePublisher(chatId: Int64) -> AnyPublisher<TelegramMessageSnapshot, Never> {
        updateStore.messagePublisher(chatId: chatId)
    }

    func mergeMessageHistory(chatId: Int64, messages: [Message]) {
        updateStore.mergeMessageHistory(chatId: chatId, messages: messages)
    }

    func replaceMessageHistory(chatId: Int64, messages: [Message]) {
        updateStore.replaceMessageHistory(chatId: chatId, messages: messages)
    }

    func mergeMessages(chatId: Int64, messages: [Message]) {
        updateStore.mergeMessages(chatId: chatId, messages: messages)
    }

    func notifyMessageContentChanged(chatId: Int64, messageId: Int64, newContent: MessageContent) {
        updateStore.publish(.updateMessageContent(UpdateMessageContent(
            chatId: chatId,
            messageId: messageId,
            newContent: newContent,
        )))
    }

    func mergeChatListChats(_ chats: [Chat]) {
        updateStore.mergeChatListChats(chats)
    }

    func mergeInitialFile(_ file: File) {
        updateStore.mergeInitialFile(file)
    }

    func start(configuration: TelegramSessionConfiguration) {
        stateLock.lock()
        self.configuration = configuration
        stateLock.unlock()

        try? client.setLogStream(logStream: .logStreamEmpty) { _ in }
        configureIfReady()
    }

    func close() {
        manager.closeClients()
    }

    // MARK: Private

    private lazy var internalClient: TDLibClient = manager.createClient { [weak self] data, client in
        guard let self else { return }
        do {
            let update = try client.decoder.decode(Update.self, from: data)
            process(update)
        } catch {
            print("TDLib update decoding failed: \(error)")
        }
    }

    private var configuration: TelegramSessionConfiguration?
    private var isConfiguringParameters = false
    private var isWaitingForParameters = false
    private let manager = TDLibClientManager()
    private let stateLock = NSLock()
    private let updateStore = TelegramUpdateStore()

    private func process(_ update: Update) {
        if case .updateAuthorizationState(let value) = update {
            if case .authorizationStateWaitTdlibParameters = value.authorizationState {
                stateLock.lock()
                isWaitingForParameters = true
                stateLock.unlock()
                configureIfReady()
            }
        }
        updateStore.publish(update)
    }

    private func configureIfReady() {
        stateLock.lock()
        guard isWaitingForParameters,
              !isConfiguringParameters,
              let configuration
        else {
            stateLock.unlock()
            return
        }
        isConfiguringParameters = true
        stateLock.unlock()

        Task { [weak self, client] in
            do {
                try await client.setTdlibParameters(
                    apiHash: configuration.apiHash,
                    apiId: configuration.apiId,
                    applicationVersion: configuration.applicationVersion,
                    databaseDirectory: configuration.databaseDirectory,
                    databaseEncryptionKey: Data(),
                    deviceModel: configuration.deviceModel,
                    filesDirectory: configuration.databaseDirectory,
                    systemLanguageCode: configuration.systemLanguageCode,
                    systemVersion: configuration.systemVersion,
                    useChatInfoDatabase: true,
                    useFileDatabase: true,
                    useMessageDatabase: true,
                    useSecretChats: true,
                    useTestDc: false,
                )
                // TDLib's notification manager defaults `notification_group_count_max` to 0
                // (`NotificationManager::DEFAULT_GROUP_COUNT_MAX`), which disables it outright -
                // it never emits `updateNotificationGroup` at all until told otherwise. 25 matches
                // Unigram's own TDLib client setup (another TDLib-based client, checked directly).
                _ = try? await client.setOption(
                    name: "notification_group_count_max",
                    value: .optionValueInteger(.init(value: 25)),
                )
            } catch {
                self?.resetConfigurationAttempt()
                print("TDLib configuration failed: \(error)")
            }
        }
    }

    private func resetConfigurationAttempt() {
        stateLock.lock()
        isConfiguringParameters = false
        stateLock.unlock()
    }
}
