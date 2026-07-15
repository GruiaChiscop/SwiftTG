import Combine
import Foundation
import TDLibKit

protocol TelegramContactsSyncing: Sendable {
    func changeImportedContacts(contacts: [ImportedContact]?) async throws -> ImportedContacts
}

protocol TelegramService: TelegramContactsSyncing, Sendable {
    var authorizationStatePublisher: AnyPublisher<AuthorizationState, Never> { get }
    var chatListPublisher: AnyPublisher<ChatListSnapshot, Never> { get }
    var updatePublisher: AnyPublisher<Update, Never> { get }

    func filePublisher(fileId: Int) -> AnyPublisher<File, Never>
    func messagePublisher(chatId: Int64) -> AnyPublisher<TelegramMessageSnapshot, Never>
    func mergeMessageHistory(chatId: Int64, messages: [Message])
    func replaceMessageHistory(chatId: Int64, messages: [Message])
    func mergeMessages(chatId: Int64, messages: [Message])
    func mergeChatListChats(_ chats: [Chat])

    func addMessageReaction(chatId: Int64?, isBig: Bool?, messageId: Int64?, reactionType: ReactionType?, updateRecentReactions: Bool?) async throws -> Ok
    func addChatToList(chatId: Int64?, chatList: ChatList?) async throws -> Ok
    func checkAuthenticationCode(code: String?) async throws -> Ok
    func checkAuthenticationPassword(password: String?) async throws -> Ok
    func closeChat(chatId: Int64?) async throws -> Ok
    func createPrivateChat(force: Bool?, userId: Int64?) async throws -> Chat
    func deleteChatHistory(chatId: Int64?, removeFromChatList: Bool?, revoke: Bool?) async throws -> Ok
    func deleteMessages(chatId: Int64?, messageIds: [Int64]?, revoke: Bool?) async throws -> Ok
    func downloadFile(fileId: Int?, limit: Int64?, offset: Int64?, priority: Int?, synchronous: Bool?) async throws -> File
    func editMessageCaption(caption: FormattedText?, chatId: Int64?, messageId: Int64?, replyMarkup: ReplyMarkup?, showCaptionAboveMedia: Bool?) async throws -> Message
    func editMessageText(chatId: Int64?, inputMessageContent: InputMessageContent?, messageId: Int64?, replyMarkup: ReplyMarkup?) async throws -> Message
    func getBasicGroup(basicGroupId: Int64?) async throws -> BasicGroup
    func getChat(chatId: Int64?) async throws -> Chat
    func getChatFolder(chatFolderId: Int?) async throws -> ChatFolder
    func getChatHistory(
        chatId: Int64?,
        fromMessageId: Int64?,
        limit: Int?,
        offset: Int?,
        onlyLocal: Bool?
    ) async throws -> Messages
    func getChats(chatList: ChatList?, limit: Int?) async throws -> Chats
    func getAuthorizationState() async throws -> AuthorizationState
    func getCountries() async throws -> Countries
    func getCountryCode() async throws -> Text
    func getMessage(chatId: Int64?, messageId: Int64?) async throws -> Message
    func getMessageAvailableReactions(
        chatId: Int64?,
        messageId: Int64?,
        rowSize: Int?
    ) async throws -> AvailableReactions
    func getMessageProperties(chatId: Int64?, messageId: Int64?) async throws -> MessageProperties
    func getSupergroup(supergroupId: Int64?) async throws -> Supergroup
    func getUser(userId: Int64?) async throws -> User
    func openChat(chatId: Int64?) async throws -> Ok
    func pinChatMessage(chatId: Int64?, disableNotification: Bool?, messageId: Int64?, onlyForSelf: Bool?) async throws -> Ok
    func sendChatAction(action: ChatAction?, businessConnectionId: String?, chatId: Int64?, topicId: MessageTopic?) async throws -> Ok
    func sendMessage(chatId: Int64?, inputMessageContent: InputMessageContent?, options: MessageSendOptions?, replyMarkup: ReplyMarkup?, replyTo: InputMessageReplyTo?, topicId: MessageTopic?) async throws -> Message
    func sendMessageAlbum(chatId: Int64?, inputMessageContents: [InputMessageContent]?, options: MessageSendOptions?, replyTo: InputMessageReplyTo?, topicId: MessageTopic?) async throws -> Messages
    func searchChats(limit: Int?, query: String?, typeFilter: SearchChatTypeFilter?) async throws -> Chats
    func searchMessages(chatList: ChatList?, chatTypeFilter: SearchMessagesChatTypeFilter?, filter: SearchMessagesFilter?, limit: Int?, maxDate: Int?, minDate: Int?, offset: String?, query: String?) async throws -> FoundMessages
    func setChatNotificationSettings(chatId: Int64?, notificationSettings: ChatNotificationSettings?) async throws -> Ok
    func setChatDraftMessage(chatId: Int64?, draftMessage: DraftMessage?, topicId: MessageTopic?) async throws -> Ok
    func setAuthenticationPhoneNumber(
        phoneNumber: String?,
        settings: PhoneNumberAuthenticationSettings?
    ) async throws -> Ok
    func toggleChatIsMarkedAsUnread(chatId: Int64?, isMarkedAsUnread: Bool?) async throws -> Ok
    func toggleChatIsPinned(chatId: Int64?, chatList: ChatList?, isPinned: Bool?) async throws -> Ok
    func unpinChatMessage(chatId: Int64?, messageId: Int64?) async throws -> Ok
    func viewMessages(chatId: Int64?, forceRead: Bool?, messageIds: [Int64]?, source: MessageSource?) async throws -> Ok
}

extension TelegramSession: TelegramService {
    func changeImportedContacts(contacts: [ImportedContact]?) async throws -> ImportedContacts {
        try await client.changeImportedContacts(contacts: contacts)
    }

    func searchChats(limit: Int?, query: String?, typeFilter: SearchChatTypeFilter?) async throws -> Chats {
        try await client.searchChats(limit: limit, query: query, typeFilter: typeFilter)
    }

    func searchMessages(
        chatList: ChatList?,
        chatTypeFilter: SearchMessagesChatTypeFilter?,
        filter: SearchMessagesFilter?,
        limit: Int?,
        maxDate: Int?,
        minDate: Int?,
        offset: String?,
        query: String?
    ) async throws -> FoundMessages {
        try await client.searchMessages(
            chatList: chatList,
            chatTypeFilter: chatTypeFilter,
            filter: filter,
            limit: limit,
            maxDate: maxDate,
            minDate: minDate,
            offset: offset,
            query: query,
        )
    }

    func addChatToList(chatId: Int64?, chatList: ChatList?) async throws -> Ok {
        try await client.addChatToList(chatId: chatId, chatList: chatList)
    }

    func addMessageReaction(chatId: Int64?, isBig: Bool?, messageId: Int64?, reactionType: ReactionType?, updateRecentReactions: Bool?) async throws -> Ok {
        try await client.addMessageReaction(chatId: chatId, isBig: isBig, messageId: messageId, reactionType: reactionType, updateRecentReactions: updateRecentReactions)
    }
    func checkAuthenticationCode(code: String?) async throws -> Ok {
        try await client.checkAuthenticationCode(code: code)
    }

    func checkAuthenticationPassword(password: String?) async throws -> Ok {
        try await client.checkAuthenticationPassword(password: password)
    }

    func closeChat(chatId: Int64?) async throws -> Ok {
        try await client.closeChat(chatId: chatId)
    }

    func createPrivateChat(force: Bool?, userId: Int64?) async throws -> Chat {
        try await client.createPrivateChat(force: force, userId: userId)
    }

    func deleteChatHistory(chatId: Int64?, removeFromChatList: Bool?, revoke: Bool?) async throws -> Ok {
        try await client.deleteChatHistory(
            chatId: chatId,
            removeFromChatList: removeFromChatList,
            revoke: revoke
        )
    }

    func deleteMessages(chatId: Int64?, messageIds: [Int64]?, revoke: Bool?) async throws -> Ok {
        try await client.deleteMessages(chatId: chatId, messageIds: messageIds, revoke: revoke)
    }

    func downloadFile(fileId: Int?, limit: Int64?, offset: Int64?, priority: Int?, synchronous: Bool?) async throws -> File {
        let file = try await client.downloadFile(
            fileId: fileId,
            limit: limit,
            offset: offset,
            priority: priority,
            synchronous: synchronous
        )
        mergeInitialFile(file)
        return file
    }

    func editMessageCaption(caption: FormattedText?, chatId: Int64?, messageId: Int64?, replyMarkup: ReplyMarkup?, showCaptionAboveMedia: Bool?) async throws -> Message {
        try await client.editMessageCaption(caption: caption, chatId: chatId, messageId: messageId, replyMarkup: replyMarkup, showCaptionAboveMedia: showCaptionAboveMedia)
    }

    func editMessageText(chatId: Int64?, inputMessageContent: InputMessageContent?, messageId: Int64?, replyMarkup: ReplyMarkup?) async throws -> Message {
        try await client.editMessageText(chatId: chatId, inputMessageContent: inputMessageContent, messageId: messageId, replyMarkup: replyMarkup)
    }

    func getBasicGroup(basicGroupId: Int64?) async throws -> BasicGroup {
        try await client.getBasicGroup(basicGroupId: basicGroupId)
    }

    func getChat(chatId: Int64?) async throws -> Chat {
        try await client.getChat(chatId: chatId)
    }

    func getChatFolder(chatFolderId: Int?) async throws -> ChatFolder {
        try await client.getChatFolder(chatFolderId: chatFolderId)
    }

    func getChatHistory(
        chatId: Int64?,
        fromMessageId: Int64?,
        limit: Int?,
        offset: Int?,
        onlyLocal: Bool?
    ) async throws -> Messages {
        let query = GetChatHistory(
            chatId: chatId,
            fromMessageId: fromMessageId,
            limit: limit,
            offset: offset,
            onlyLocal: onlyLocal,
        )
        let dto = DTO(query, encoder: client.encoder)
        let data: Data = try await withCheckedThrowingContinuation { continuation in
            do {
                try client.send(query: dto) { responseData in
                    continuation.resume(returning: responseData)
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
        return try decodeHistoryResponse(data)
    }

    private func decodeHistoryResponse(_ data: Data) throws -> Messages {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TelegramHistoryLoadingError.invalidResponse
        }
        if object["@type"] as? String == "error" {
            throw TelegramHistoryLoadingError.tdlib(
                code: object["code"] as? Int ?? 0,
                message: object["message"] as? String ?? "Unknown TDLib error",
            )
        }

        let rawMessages = object["messages"] as? [[String: Any]] ?? []
        var messages = [Message]()
        messages.reserveCapacity(rawMessages.count)
        for rawMessage in rawMessages {
            guard let messageData = try? JSONSerialization.data(withJSONObject: rawMessage),
                  let message = try? client.decoder.decode(Message.self, from: messageData)
            else { continue }
            messages.append(message)
        }
        return Messages(
            messages: messages,
            totalCount: object["total_count"] as? Int ?? messages.count,
        )
    }

    func getChats(chatList: ChatList?, limit: Int?) async throws -> Chats {
        try await client.getChats(chatList: chatList, limit: limit)
    }

    func getAuthorizationState() async throws -> AuthorizationState {
        try await client.getAuthorizationState()
    }

    func getCountries() async throws -> Countries {
        try await client.getCountries()
    }

    func getCountryCode() async throws -> Text {
        try await client.getCountryCode()
    }

    func getMessage(chatId: Int64?, messageId: Int64?) async throws -> Message {
        try await client.getMessage(chatId: chatId, messageId: messageId)
    }

    func getMessageAvailableReactions(
        chatId: Int64?,
        messageId: Int64?,
        rowSize: Int?
    ) async throws -> AvailableReactions {
        try await client.getMessageAvailableReactions(chatId: chatId, messageId: messageId, rowSize: rowSize)
    }

    func getMessageProperties(chatId: Int64?, messageId: Int64?) async throws -> MessageProperties {
        try await client.getMessageProperties(chatId: chatId, messageId: messageId)
    }

    func getSupergroup(supergroupId: Int64?) async throws -> Supergroup {
        try await client.getSupergroup(supergroupId: supergroupId)
    }

    func getUser(userId: Int64?) async throws -> User {
        try await client.getUser(userId: userId)
    }

    func openChat(chatId: Int64?) async throws -> Ok {
        try await client.openChat(chatId: chatId)
    }

    func pinChatMessage(chatId: Int64?, disableNotification: Bool?, messageId: Int64?, onlyForSelf: Bool?) async throws -> Ok {
        try await client.pinChatMessage(chatId: chatId, disableNotification: disableNotification, messageId: messageId, onlyForSelf: onlyForSelf)
    }

    func sendChatAction(action: ChatAction?, businessConnectionId: String?, chatId: Int64?, topicId: MessageTopic?) async throws -> Ok {
        try await client.sendChatAction(action: action, businessConnectionId: businessConnectionId, chatId: chatId, topicId: topicId)
    }

    func sendMessage(chatId: Int64?, inputMessageContent: InputMessageContent?, options: MessageSendOptions?, replyMarkup: ReplyMarkup?, replyTo: InputMessageReplyTo?, topicId: MessageTopic?) async throws -> Message {
        try await client.sendMessage(chatId: chatId, inputMessageContent: inputMessageContent, options: options, replyMarkup: replyMarkup, replyTo: replyTo, topicId: topicId)
    }

    func sendMessageAlbum(chatId: Int64?, inputMessageContents: [InputMessageContent]?, options: MessageSendOptions?, replyTo: InputMessageReplyTo?, topicId: MessageTopic?) async throws -> Messages {
        try await client.sendMessageAlbum(chatId: chatId, inputMessageContents: inputMessageContents, options: options, replyTo: replyTo, topicId: topicId)
    }

    func setChatNotificationSettings(chatId: Int64?, notificationSettings: ChatNotificationSettings?) async throws -> Ok {
        try await client.setChatNotificationSettings(
            chatId: chatId,
            notificationSettings: notificationSettings
        )
    }

    func setChatDraftMessage(chatId: Int64?, draftMessage: DraftMessage?, topicId: MessageTopic?) async throws -> Ok {
        try await client.setChatDraftMessage(chatId: chatId, draftMessage: draftMessage, topicId: topicId)
    }

    func setAuthenticationPhoneNumber(
        phoneNumber: String?,
        settings: PhoneNumberAuthenticationSettings?
    ) async throws -> Ok {
        try await client.setAuthenticationPhoneNumber(phoneNumber: phoneNumber, settings: settings)
    }

    func toggleChatIsMarkedAsUnread(chatId: Int64?, isMarkedAsUnread: Bool?) async throws -> Ok {
        try await client.toggleChatIsMarkedAsUnread(
            chatId: chatId,
            isMarkedAsUnread: isMarkedAsUnread
        )
    }

    func toggleChatIsPinned(chatId: Int64?, chatList: ChatList?, isPinned: Bool?) async throws -> Ok {
        try await client.toggleChatIsPinned(
            chatId: chatId,
            chatList: chatList,
            isPinned: isPinned
        )
    }

    func unpinChatMessage(chatId: Int64?, messageId: Int64?) async throws -> Ok {
        try await client.unpinChatMessage(chatId: chatId, messageId: messageId)
    }

    func viewMessages(chatId: Int64?, forceRead: Bool?, messageIds: [Int64]?, source: MessageSource?) async throws -> Ok {
        try await client.viewMessages(chatId: chatId, forceRead: forceRead, messageIds: messageIds, source: source)
    }
}

private enum TelegramHistoryLoadingError: LocalizedError {
    case invalidResponse
    case tdlib(code: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "TDLib returned an invalid history response."
        case .tdlib(let code, let message):
            "TDLib history error \(code): \(message)"
        }
    }
}
