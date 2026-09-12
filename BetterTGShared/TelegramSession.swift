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
        self.internalClient = makeClient()
    }

    // MARK: Internal

    var client: TDLibClient {
        stateLock.lock()
        defer { stateLock.unlock() }
        return internalClient
    }

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

        configureIfReady()
    }

    func close() {
        stateLock.lock()
        isClosingSession = true
        stateLock.unlock()
        manager.closeClients()
    }

    // MARK: Private

    private var internalClient: TDLibClient!
    private var configuration: TelegramSessionConfiguration?
    private var configuringClientId: Int32?
    private var isConfiguringParameters = false
    private var isClosingSession = false
    private var isReplacingClient = false
    private var isWaitingForParameters = false
    private let manager = TDLibClientManager()
    private let stateLock = NSLock()
    private let updateStore = TelegramUpdateStore()

    private func decodeUpdate(from data: Data, using decoder: JSONDecoder) throws -> Update {
        do {
            return try decoder.decode(Update.self, from: data)
        } catch let originalError {
            // Foundation's convertFromSnakeCase maps `p2p` to `P2P`, while TDLibKit's
            // generated Swift properties are named `P2p`. Normalize only the two TDLib call
            // keys affected by this acronym/number edge case, then retry the failed update.
            guard let compatibleData = TDLibJSONCompatibility.normalizingCallP2PKeys(in: data),
                  compatibleData != data
            else {
                throw originalError
            }
            return try decoder.decode(Update.self, from: compatibleData)
        }
    }

    private func makeClient() -> TDLibClient {
        let client = manager.createClient { [weak self] data, client in
            guard let self else { return }
            do {
                let update = try decodeUpdate(from: data, using: client.decoder)
                process(update, from: client)
            } catch {
                print("TDLib update decoding failed: \(error)")
            }
        }
        try? client.setLogStream(logStream: .logStreamEmpty) { _ in }
        return client
    }

    private func process(_ update: Update, from client: TDLibClient) {
        if case .updateAuthorizationState(let value) = update {
            switch value.authorizationState {
            case .authorizationStateWaitTdlibParameters:
                stateLock.lock()
                isWaitingForParameters = true
                stateLock.unlock()
                configureIfReady()
            case .authorizationStateClosed:
                replaceClosedClientIfNeeded(client)
            default:
                break
            }
        }
        updateStore.publish(update)
    }

    private func configureIfReady() {
        stateLock.lock()
        guard isWaitingForParameters,
              !isConfiguringParameters,
              !isReplacingClient,
              let configuration
        else {
            stateLock.unlock()
            return
        }
        // Read the current client under the lock, after the guard, so a `replaceClosedClientIfNeeded`
        // swap can't leave this configuring the stale (closed) instance.
        let activeClient = internalClient!
        isConfiguringParameters = true
        configuringClientId = activeClient.id
        stateLock.unlock()

        Task { [weak self, activeClient] in
            do {
                try await activeClient.setTdlibParameters(
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
                _ = try? await activeClient.setOption(
                    name: "notification_group_count_max",
                    value: .optionValueInteger(.init(value: 25)),
                )
                self?.finishConfiguration(clientId: activeClient.id, succeeded: true)
            } catch {
                self?.finishConfiguration(clientId: activeClient.id, succeeded: false)
                print("TDLib configuration failed: \(error)")
            }
        }
    }

    private func finishConfiguration(clientId: Int32, succeeded: Bool) {
        stateLock.lock()
        guard configuringClientId == clientId else {
            stateLock.unlock()
            return
        }
        isConfiguringParameters = false
        configuringClientId = nil
        if succeeded {
            isWaitingForParameters = false
        }
        stateLock.unlock()
    }

    /// `authorizationStateClosed` is terminal for a TDLib client. Logging out closes that client,
    /// so continuing with the same instance leaves every subsequent login request unanswered.
    /// Create a fresh client unless the app itself is terminating and deliberately closing TDLib.
    private func replaceClosedClientIfNeeded(_ closedClient: TDLibClient) {
        stateLock.lock()
        guard !isClosingSession,
              !isReplacingClient,
              internalClient === closedClient
        else {
            stateLock.unlock()
            return
        }
        isReplacingClient = true
        isConfiguringParameters = false
        configuringClientId = nil
        stateLock.unlock()

        updateStore.reset()
        let replacement = makeClient()

        stateLock.lock()
        internalClient = replacement
        isReplacingClient = false
        stateLock.unlock()

        // The replacement's own `authorizationStateWaitTdlibParameters` may already have been
        // processed (and skipped, because `isReplacingClient` was set) before `internalClient`
        // pointed at it. Re-drive configuration now that it does; it's a no-op otherwise.
        configureIfReady()
    }
}

// MARK: - TDLibJSONCompatibility

private enum TDLibJSONCompatibility {
    // MARK: Internal

    static func normalizingCallP2PKeys(in data: Data) -> Data? {
        guard let json = try? JSONSerialization.jsonObject(with: data),
              let normalized = normalize(json),
              JSONSerialization.isValidJSONObject(normalized)
        else {
            return nil
        }
        return try? JSONSerialization.data(withJSONObject: normalized)
    }

    // MARK: Private

    private static func normalize(_ value: Any) -> Any? {
        if let dictionary = value as? [String: Any] {
            return dictionary.reduce(into: [String: Any]()) { result, element in
                let key =
                    switch element.key {
                    case "allow_p2p":
                        "allowP2p"
                    case "udp_p2p":
                        "udpP2p"
                    default:
                        element.key
                    }
                result[key] = normalize(element.value)
            }
        }
        if let array = value as? [Any] {
            return array.compactMap(normalize)
        }
        return value
    }
}
