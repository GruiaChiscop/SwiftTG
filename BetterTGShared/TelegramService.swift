// TelegramService.swift

import Combine
import Foundation
import TDLibKit

// MARK: - TelegramContactsSyncing

protocol TelegramContactsSyncing: Sendable {
    func changeImportedContacts(contacts: [ImportedContact]?) async throws -> ImportedContacts
}

// MARK: - TelegramService

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
    /// Feeds a synthetic `updateMessageContent` through the same pipeline a real TDLib push update
    /// would use. TDLib doesn't push `updateMessageEdited`/`updateMessageContent` back to the
    /// client that made the edit (only to other sessions), so the editing client has to notify
    /// itself using the `Message` its own edit call already returned.
    func notifyMessageContentChanged(chatId: Int64, messageId: Int64, newContent: MessageContent)

    func addMessageReaction(
        chatId: Int64?,
        isBig: Bool?,
        messageId: Int64?,
        reactionType: ReactionType?,
        updateRecentReactions: Bool?,
    ) async throws -> Ok
    func removeMessageReaction(chatId: Int64?, messageId: Int64?, reactionType: ReactionType?) async throws -> Ok
    func addChatToList(chatId: Int64?, chatList: ChatList?) async throws -> Ok
    func cancelDownloadFile(fileId: Int?, onlyIfPending: Bool?) async throws -> Ok
    func checkAuthenticationCode(code: String?) async throws -> Ok
    func checkAuthenticationPassword(password: String?) async throws -> Ok
    func closeChat(chatId: Int64?) async throws -> Ok
    func createBasicGroupChat(basicGroupId: Int64?, force: Bool?) async throws -> Chat
    func createPrivateChat(force: Bool?, userId: Int64?) async throws -> Chat
    func createSupergroupChat(force: Bool?, supergroupId: Int64?) async throws -> Chat
    func deleteChat(chatId: Int64?) async throws -> Ok
    func deleteChatHistory(chatId: Int64?, removeFromChatList: Bool?, revoke: Bool?) async throws -> Ok
    func deleteMessages(chatId: Int64?, messageIds: [Int64]?, revoke: Bool?) async throws -> Ok
    func downloadFile(fileId: Int?, limit: Int64?, offset: Int64?, priority: Int?, synchronous: Bool?) async throws
        -> File
    func editMessageCaption(
        caption: FormattedText?,
        chatId: Int64?,
        messageId: Int64?,
        replyMarkup: ReplyMarkup?,
        showCaptionAboveMedia: Bool?,
    ) async throws -> Message
    func editMessageText(
        chatId: Int64?,
        inputMessageContent: InputMessageContent?,
        messageId: Int64?,
        replyMarkup: ReplyMarkup?,
    ) async throws -> Message
    func forwardMessages(
        chatId: Int64?,
        fromChatId: Int64?,
        messageIds: [Int64]?,
        options: MessageSendOptions?,
        removeCaption: Bool?,
        sendCopy: Bool?,
        topicId: MessageTopic?,
    ) async throws -> Messages
    func getBasicGroup(basicGroupId: Int64?) async throws -> BasicGroup
    func getBasicGroupFullInfo(basicGroupId: Int64?) async throws -> BasicGroupFullInfo
    func getChat(chatId: Int64?) async throws -> Chat
    func getChatFolder(chatFolderId: Int?) async throws -> ChatFolder
    func getChatScheduledMessages(chatId: Int64?) async throws -> Messages
    func editMessageSchedulingState(
        chatId: Int64?,
        messageId: Int64?,
        schedulingState: MessageSchedulingState?,
    ) async throws -> Ok
    func getChatHistory(
        chatId: Int64?,
        fromMessageId: Int64?,
        limit: Int?,
        offset: Int?,
        onlyLocal: Bool?,
    ) async throws -> Messages
    func getChats(chatList: ChatList?, limit: Int?) async throws -> Chats
    func getContacts() async throws -> Users
    func getAuthorizationState() async throws -> AuthorizationState
    func getCountries() async throws -> Countries
    func getCountryCode() async throws -> Text
    func getGroupsInCommon(limit: Int?, offsetChatId: Int64?, userId: Int64?) async throws -> Chats
    func getStorageStatisticsFast() async throws -> StorageStatisticsFast
    func getInstalledStickerSets(stickerType: StickerType?) async throws -> StickerSets
    func getMessage(chatId: Int64?, messageId: Int64?) async throws -> Message
    func getMessageAvailableReactions(
        chatId: Int64?,
        messageId: Int64?,
        rowSize: Int?,
    ) async throws -> AvailableReactions
    func getMessageAddedReactions(
        chatId: Int64?,
        limit: Int?,
        messageId: Int64?,
        offset: String?,
        reactionType: ReactionType?,
    ) async throws -> AddedReactions
    func getMessageProperties(chatId: Int64?, messageId: Int64?) async throws -> MessageProperties
    func getPollVoters(
        chatId: Int64?,
        limit: Int?,
        messageId: Int64?,
        offset: Int?,
        optionId: Int?,
    ) async throws -> PollVoters
    func getRecentStickers(isAttached: Bool?) async throws -> Stickers
    func getStickerSet(setId: TdInt64?) async throws -> StickerSet
    func getStickers(
        chatId: Int64?,
        limit: Int?,
        query: String?,
        stickerType: StickerType?,
    ) async throws -> Stickers
    func getLinkPreview(linkPreviewOptions: LinkPreviewOptions?, text: FormattedText?) async throws -> LinkPreview
    func getMe() async throws -> User
    func getScopeNotificationSettings(scope: NotificationSettingsScope?) async throws -> ScopeNotificationSettings
    func getSupergroup(supergroupId: Int64?) async throws -> Supergroup
    func getSupergroupFullInfo(supergroupId: Int64?) async throws -> SupergroupFullInfo
    func getTextEntities(text: String?) async throws -> TextEntities
    func getUser(userId: Int64?) async throws -> User
    func translateMessageText(
        chatId: Int64?,
        messageId: Int64?,
        toLanguageCode: String?,
        tone: String?,
    ) async throws -> FormattedText
    func importContacts(contacts: [ImportedContact]?) async throws -> ImportedContacts
    func getUserFullInfo(userId: Int64?) async throws -> UserFullInfo
    func getSupergroupMembers(
        filter: SupergroupMembersFilter?,
        limit: Int?,
        offset: Int?,
        supergroupId: Int64?,
    ) async throws -> ChatMembers
    func leaveChat(chatId: Int64?) async throws -> Ok
    func openChat(chatId: Int64?) async throws -> Ok
    func pinChatMessage(chatId: Int64?, disableNotification: Bool?, messageId: Int64?, onlyForSelf: Bool?) async throws
        -> Ok
    func processPushNotification(payload: String?) async throws -> Ok
    func registerDevice(deviceToken: DeviceToken?, otherUserIds: [Int64]?) async throws -> PushReceiverId
    func sendChatAction(
        action: ChatAction?,
        businessConnectionId: String?,
        chatId: Int64?,
        topicId: MessageTopic?,
    ) async throws -> Ok
    func sendMessage(
        chatId: Int64?,
        inputMessageContent: InputMessageContent?,
        options: MessageSendOptions?,
        replyMarkup: ReplyMarkup?,
        replyTo: InputMessageReplyTo?,
        topicId: MessageTopic?,
    ) async throws -> Message
    func sendMessageAlbum(
        chatId: Int64?,
        inputMessageContents: [InputMessageContent]?,
        options: MessageSendOptions?,
        replyTo: InputMessageReplyTo?,
        topicId: MessageTopic?,
    ) async throws -> Messages
    func searchChats(limit: Int?, query: String?, typeFilter: SearchChatTypeFilter?) async throws -> Chats
    func searchChatMembers(
        chatId: Int64?,
        filter: ChatMembersFilter?,
        limit: Int?,
        query: String?,
    ) async throws -> ChatMembers
    func searchChatMessages(
        chatId: Int64?,
        filter: SearchMessagesFilter?,
        fromMessageId: Int64?,
        limit: Int?,
        offset: Int?,
        query: String?,
        senderId: MessageSender?,
        topicId: MessageTopic?,
    ) async throws -> FoundChatMessages
    func searchMessages(
        chatList: ChatList?,
        chatTypeFilter: SearchMessagesChatTypeFilter?,
        filter: SearchMessagesFilter?,
        limit: Int?,
        maxDate: Int?,
        minDate: Int?,
        offset: String?,
        query: String?,
    ) async throws -> FoundMessages
    func searchSecretMessages(
        chatId: Int64?,
        filter: SearchMessagesFilter?,
        limit: Int?,
        offset: String?,
        query: String?,
    ) async throws -> FoundMessages
    func setChatNotificationSettings(chatId: Int64?, notificationSettings: ChatNotificationSettings?) async throws -> Ok
    func setChatDraftMessage(chatId: Int64?, draftMessage: DraftMessage?, topicId: MessageTopic?) async throws -> Ok
    func setAuthenticationPhoneNumber(
        phoneNumber: String?,
        settings: PhoneNumberAuthenticationSettings?,
    ) async throws -> Ok
    func setMessageSenderBlockList(blockList: BlockList?, senderId: MessageSender?) async throws -> Ok
    func setOption(name: String?, value: OptionValue?) async throws -> Ok
    func setPollAnswer(chatId: Int64?, messageId: Int64?, optionIds: [Int]?) async throws -> Ok
    func markChecklistTasksAsDone(
        chatId: Int64?,
        markedAsDoneTaskIds: [Int]?,
        markedAsNotDoneTaskIds: [Int]?,
        messageId: Int64?,
    ) async throws -> Ok
    func toggleChatIsMarkedAsUnread(chatId: Int64?, isMarkedAsUnread: Bool?) async throws -> Ok
    func toggleChatIsPinned(chatId: Int64?, chatList: ChatList?, isPinned: Bool?) async throws -> Ok
    func unpinChatMessage(chatId: Int64?, messageId: Int64?) async throws -> Ok
    func viewMessages(chatId: Int64?, forceRead: Bool?, messageIds: [Int64]?, source: MessageSource?) async throws -> Ok
    func optimizeStorage(
        chatIds: [Int64]?,
        chatLimit: Int?,
        count: Int?,
        excludeChatIds: [Int64]?,
        fileTypes: [FileType]?,
        immunityDelay: Int?,
        returnDeletedFileStatistics: Bool?,
        size: Int64?,
        ttl: Int?,
    ) async throws -> StorageStatistics
}

// MARK: - TelegramSession + TelegramService

extension TelegramSession: TelegramService {
    func getStorageStatisticsFast() async throws -> StorageStatisticsFast {
        try await client.getStorageStatisticsFast()
    }

    func setOption(name: String?, value: OptionValue?) async throws -> Ok {
        try await client.setOption(name: name, value: value)
    }

    func optimizeStorage(
        chatIds: [Int64]?,
        chatLimit: Int?,
        count: Int?,
        excludeChatIds: [Int64]?,
        fileTypes: [FileType]?,
        immunityDelay: Int?,
        returnDeletedFileStatistics: Bool?,
        size: Int64?,
        ttl: Int?,
    ) async throws -> StorageStatistics {
        try await client.optimizeStorage(
            chatIds: chatIds,
            chatLimit: chatLimit,
            count: count,
            excludeChatIds: excludeChatIds,
            fileTypes: fileTypes,
            immunityDelay: immunityDelay,
            returnDeletedFileStatistics: returnDeletedFileStatistics,
            size: size,
            ttl: ttl,
        )
    }

    func getTextEntities(text: String?) async throws -> TextEntities {
        try await client.getTextEntities(text: text)
    }

    func cancelDownloadFile(fileId: Int?, onlyIfPending: Bool?) async throws -> Ok {
        try await client.cancelDownloadFile(fileId: fileId, onlyIfPending: onlyIfPending)
    }

    func processPushNotification(payload: String?) async throws -> Ok {
        try await client.processPushNotification(payload: payload)
    }

    func registerDevice(deviceToken: DeviceToken?, otherUserIds: [Int64]?) async throws -> PushReceiverId {
        try await client.registerDevice(deviceToken: deviceToken, otherUserIds: otherUserIds)
    }

    func changeImportedContacts(contacts: [ImportedContact]?) async throws -> ImportedContacts {
        try await client.changeImportedContacts(contacts: contacts)
    }

    func getContacts() async throws -> Users {
        try await client.getContacts()
    }

    func importContacts(contacts: [ImportedContact]?) async throws -> ImportedContacts {
        try await client.importContacts(contacts: contacts)
    }

    func createBasicGroupChat(basicGroupId: Int64?, force: Bool?) async throws -> Chat {
        try await client.createBasicGroupChat(basicGroupId: basicGroupId, force: force)
    }

    func createSupergroupChat(force: Bool?, supergroupId: Int64?) async throws -> Chat {
        try await client.createSupergroupChat(force: force, supergroupId: supergroupId)
    }

    func deleteChat(chatId: Int64?) async throws -> Ok {
        try await client.deleteChat(chatId: chatId)
    }

    func searchChats(limit: Int?, query: String?, typeFilter: SearchChatTypeFilter?) async throws -> Chats {
        try await client.searchChats(limit: limit, query: query, typeFilter: typeFilter)
    }

    func searchChatMembers(
        chatId: Int64?,
        filter: ChatMembersFilter?,
        limit: Int?,
        query: String?,
    ) async throws -> ChatMembers {
        try await client.searchChatMembers(chatId: chatId, filter: filter, limit: limit, query: query)
    }

    func searchChatMessages(
        chatId: Int64?,
        filter: SearchMessagesFilter?,
        fromMessageId: Int64?,
        limit: Int?,
        offset: Int?,
        query: String?,
        senderId: MessageSender?,
        topicId: MessageTopic?,
    ) async throws -> FoundChatMessages {
        try await client.searchChatMessages(
            chatId: chatId,
            filter: filter,
            fromMessageId: fromMessageId,
            limit: limit,
            offset: offset,
            query: query,
            senderId: senderId,
            topicId: topicId,
        )
    }

    func searchMessages(
        chatList: ChatList?,
        chatTypeFilter: SearchMessagesChatTypeFilter?,
        filter: SearchMessagesFilter?,
        limit: Int?,
        maxDate: Int?,
        minDate: Int?,
        offset: String?,
        query: String?,
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

    func searchSecretMessages(
        chatId: Int64?,
        filter: SearchMessagesFilter?,
        limit: Int?,
        offset: String?,
        query: String?,
    ) async throws -> FoundMessages {
        try await client.searchSecretMessages(
            chatId: chatId,
            filter: filter,
            limit: limit,
            offset: offset,
            query: query,
        )
    }

    func addChatToList(chatId: Int64?, chatList: ChatList?) async throws -> Ok {
        try await client.addChatToList(chatId: chatId, chatList: chatList)
    }

    func addMessageReaction(
        chatId: Int64?,
        isBig: Bool?,
        messageId: Int64?,
        reactionType: ReactionType?,
        updateRecentReactions: Bool?,
    ) async throws -> Ok {
        try await client.addMessageReaction(
            chatId: chatId,
            isBig: isBig,
            messageId: messageId,
            reactionType: reactionType,
            updateRecentReactions: updateRecentReactions,
        )
    }

    func removeMessageReaction(chatId: Int64?, messageId: Int64?, reactionType: ReactionType?) async throws -> Ok {
        try await client.removeMessageReaction(
            chatId: chatId,
            messageId: messageId,
            reactionType: reactionType,
        )
    }

    func getMessageAddedReactions(
        chatId: Int64?,
        limit: Int?,
        messageId: Int64?,
        offset: String?,
        reactionType: ReactionType?,
    ) async throws -> AddedReactions {
        try await client.getMessageAddedReactions(
            chatId: chatId,
            limit: limit,
            messageId: messageId,
            offset: offset,
            reactionType: reactionType,
        )
    }

    func getPollVoters(
        chatId: Int64?,
        limit: Int?,
        messageId: Int64?,
        offset: Int?,
        optionId: Int?,
    ) async throws -> PollVoters {
        try await client.getPollVoters(
            chatId: chatId,
            limit: limit,
            messageId: messageId,
            offset: offset,
            optionId: optionId,
        )
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
            revoke: revoke,
        )
    }

    func deleteMessages(chatId: Int64?, messageIds: [Int64]?, revoke: Bool?) async throws -> Ok {
        try await client.deleteMessages(chatId: chatId, messageIds: messageIds, revoke: revoke)
    }

    func downloadFile(
        fileId: Int?,
        limit: Int64?,
        offset: Int64?,
        priority: Int?,
        synchronous: Bool?,
    ) async throws -> File {
        let file = try await client.downloadFile(
            fileId: fileId,
            limit: limit,
            offset: offset,
            priority: priority,
            synchronous: synchronous,
        )
        mergeInitialFile(file)
        return file
    }

    func editMessageCaption(
        caption: FormattedText?,
        chatId: Int64?,
        messageId: Int64?,
        replyMarkup: ReplyMarkup?,
        showCaptionAboveMedia: Bool?,
    ) async throws -> Message {
        try await client.editMessageCaption(
            caption: caption,
            chatId: chatId,
            messageId: messageId,
            replyMarkup: replyMarkup,
            showCaptionAboveMedia: showCaptionAboveMedia,
        )
    }

    func forwardMessages(
        chatId: Int64?,
        fromChatId: Int64?,
        messageIds: [Int64]?,
        options: MessageSendOptions?,
        removeCaption: Bool?,
        sendCopy: Bool?,
        topicId: MessageTopic?,
    ) async throws -> Messages {
        try await client.forwardMessages(
            chatId: chatId,
            fromChatId: fromChatId,
            messageIds: messageIds,
            options: options,
            removeCaption: removeCaption,
            sendCopy: sendCopy,
            topicId: topicId,
        )
    }

    func editMessageText(
        chatId: Int64?,
        inputMessageContent: InputMessageContent?,
        messageId: Int64?,
        replyMarkup: ReplyMarkup?,
    ) async throws -> Message {
        try await client.editMessageText(
            chatId: chatId,
            inputMessageContent: inputMessageContent,
            messageId: messageId,
            replyMarkup: replyMarkup,
        )
    }

    func getBasicGroup(basicGroupId: Int64?) async throws -> BasicGroup {
        try await client.getBasicGroup(basicGroupId: basicGroupId)
    }

    func getBasicGroupFullInfo(basicGroupId: Int64?) async throws -> BasicGroupFullInfo {
        try await client.getBasicGroupFullInfo(basicGroupId: basicGroupId)
    }

    func getChat(chatId: Int64?) async throws -> Chat {
        try await client.getChat(chatId: chatId)
    }

    func getChatFolder(chatFolderId: Int?) async throws -> ChatFolder {
        try await client.getChatFolder(chatFolderId: chatFolderId)
    }

    func getChatScheduledMessages(chatId: Int64?) async throws -> Messages {
        try await client.getChatScheduledMessages(chatId: chatId)
    }

    func editMessageSchedulingState(
        chatId: Int64?,
        messageId: Int64?,
        schedulingState: MessageSchedulingState?,
    ) async throws -> Ok {
        try await client.editMessageSchedulingState(
            chatId: chatId,
            messageId: messageId,
            schedulingState: schedulingState,
        )
    }

    /// Deliberately bypasses TDLibKit's typed `client.getChatHistory(...)`, which decodes the
    /// whole `Messages` response in one shot: if a single message in the batch has a content
    /// type the locally-vendored model doesn't recognize, the entire page fails to decode. This
    /// decodes each message individually and skips ones that fail, so one unrecognized message
    /// doesn't drop the whole page.
    func getChatHistory(
        chatId: Int64?,
        fromMessageId: Int64?,
        limit: Int?,
        offset: Int?,
        onlyLocal: Bool?,
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

    func getGroupsInCommon(limit: Int?, offsetChatId: Int64?, userId: Int64?) async throws -> Chats {
        try await client.getGroupsInCommon(limit: limit, offsetChatId: offsetChatId, userId: userId)
    }

    func getInstalledStickerSets(stickerType: StickerType?) async throws -> StickerSets {
        try await client.getInstalledStickerSets(stickerType: stickerType)
    }

    func getMessage(chatId: Int64?, messageId: Int64?) async throws -> Message {
        try await client.getMessage(chatId: chatId, messageId: messageId)
    }

    func getMessageAvailableReactions(
        chatId: Int64?,
        messageId: Int64?,
        rowSize: Int?,
    ) async throws -> AvailableReactions {
        try await client.getMessageAvailableReactions(chatId: chatId, messageId: messageId, rowSize: rowSize)
    }

    func getMessageProperties(chatId: Int64?, messageId: Int64?) async throws -> MessageProperties {
        try await client.getMessageProperties(chatId: chatId, messageId: messageId)
    }

    func getRecentStickers(isAttached: Bool?) async throws -> Stickers {
        try await client.getRecentStickers(isAttached: isAttached)
    }

    func getStickerSet(setId: TdInt64?) async throws -> StickerSet {
        try await client.getStickerSet(setId: setId)
    }

    func getStickers(
        chatId: Int64?,
        limit: Int?,
        query: String?,
        stickerType: StickerType?,
    ) async throws -> Stickers {
        try await client.getStickers(
            chatId: chatId,
            limit: limit,
            query: query,
            stickerType: stickerType,
        )
    }

    func getLinkPreview(linkPreviewOptions: LinkPreviewOptions?, text: FormattedText?) async throws -> LinkPreview {
        try await client.getLinkPreview(linkPreviewOptions: linkPreviewOptions, text: text)
    }

    func getMe() async throws -> User {
        try await client.getMe()
    }

    func getScopeNotificationSettings(scope: NotificationSettingsScope?) async throws -> ScopeNotificationSettings {
        try await client.getScopeNotificationSettings(scope: scope)
    }

    func getSupergroup(supergroupId: Int64?) async throws -> Supergroup {
        try await client.getSupergroup(supergroupId: supergroupId)
    }

    func getSupergroupFullInfo(supergroupId: Int64?) async throws -> SupergroupFullInfo {
        try await client.getSupergroupFullInfo(supergroupId: supergroupId)
    }

    func getUser(userId: Int64?) async throws -> User {
        try await client.getUser(userId: userId)
    }

    func translateMessageText(
        chatId: Int64?,
        messageId: Int64?,
        toLanguageCode: String?,
        tone: String?,
    ) async throws -> FormattedText {
        try await client.translateMessageText(
            chatId: chatId,
            messageId: messageId,
            toLanguageCode: toLanguageCode,
            tone: tone,
        )
    }

    func getUserFullInfo(userId: Int64?) async throws -> UserFullInfo {
        try await client.getUserFullInfo(userId: userId)
    }

    func getSupergroupMembers(
        filter: SupergroupMembersFilter?,
        limit: Int?,
        offset: Int?,
        supergroupId: Int64?,
    ) async throws -> ChatMembers {
        try await client.getSupergroupMembers(
            filter: filter,
            limit: limit,
            offset: offset,
            supergroupId: supergroupId,
        )
    }

    func leaveChat(chatId: Int64?) async throws -> Ok {
        try await client.leaveChat(chatId: chatId)
    }

    func openChat(chatId: Int64?) async throws -> Ok {
        try await client.openChat(chatId: chatId)
    }

    func pinChatMessage(
        chatId: Int64?,
        disableNotification: Bool?,
        messageId: Int64?,
        onlyForSelf: Bool?,
    ) async throws -> Ok {
        try await client.pinChatMessage(
            chatId: chatId,
            disableNotification: disableNotification,
            messageId: messageId,
            onlyForSelf: onlyForSelf,
        )
    }

    func sendChatAction(
        action: ChatAction?,
        businessConnectionId: String?,
        chatId: Int64?,
        topicId: MessageTopic?,
    ) async throws -> Ok {
        try await client.sendChatAction(
            action: action,
            businessConnectionId: businessConnectionId,
            chatId: chatId,
            topicId: topicId,
        )
    }

    func sendMessage(
        chatId: Int64?,
        inputMessageContent: InputMessageContent?,
        options: MessageSendOptions?,
        replyMarkup: ReplyMarkup?,
        replyTo: InputMessageReplyTo?,
        topicId: MessageTopic?,
    ) async throws -> Message {
        try await client.sendMessage(
            chatId: chatId,
            inputMessageContent: inputMessageContent,
            options: options,
            replyMarkup: replyMarkup,
            replyTo: replyTo,
            topicId: topicId,
        )
    }

    func sendMessageAlbum(
        chatId: Int64?,
        inputMessageContents: [InputMessageContent]?,
        options: MessageSendOptions?,
        replyTo: InputMessageReplyTo?,
        topicId: MessageTopic?,
    ) async throws -> Messages {
        try await client.sendMessageAlbum(
            chatId: chatId,
            inputMessageContents: inputMessageContents,
            options: options,
            replyTo: replyTo,
            topicId: topicId,
        )
    }

    func setChatNotificationSettings(
        chatId: Int64?,
        notificationSettings: ChatNotificationSettings?,
    ) async throws -> Ok {
        try await client.setChatNotificationSettings(
            chatId: chatId,
            notificationSettings: notificationSettings,
        )
    }

    func setMessageSenderBlockList(blockList: BlockList?, senderId: MessageSender?) async throws -> Ok {
        try await client.setMessageSenderBlockList(blockList: blockList, senderId: senderId)
    }

    func setPollAnswer(chatId: Int64?, messageId: Int64?, optionIds: [Int]?) async throws -> Ok {
        try await client.setPollAnswer(chatId: chatId, messageId: messageId, optionIds: optionIds)
    }

    func markChecklistTasksAsDone(
        chatId: Int64?,
        markedAsDoneTaskIds: [Int]?,
        markedAsNotDoneTaskIds: [Int]?,
        messageId: Int64?,
    ) async throws -> Ok {
        try await client.markChecklistTasksAsDone(
            chatId: chatId,
            markedAsDoneTaskIds: markedAsDoneTaskIds,
            markedAsNotDoneTaskIds: markedAsNotDoneTaskIds,
            messageId: messageId,
        )
    }

    func setChatDraftMessage(chatId: Int64?, draftMessage: DraftMessage?, topicId: MessageTopic?) async throws -> Ok {
        try await client.setChatDraftMessage(chatId: chatId, draftMessage: draftMessage, topicId: topicId)
    }

    func setAuthenticationPhoneNumber(
        phoneNumber: String?,
        settings: PhoneNumberAuthenticationSettings?,
    ) async throws -> Ok {
        try await client.setAuthenticationPhoneNumber(phoneNumber: phoneNumber, settings: settings)
    }

    func toggleChatIsMarkedAsUnread(chatId: Int64?, isMarkedAsUnread: Bool?) async throws -> Ok {
        try await client.toggleChatIsMarkedAsUnread(
            chatId: chatId,
            isMarkedAsUnread: isMarkedAsUnread,
        )
    }

    func toggleChatIsPinned(chatId: Int64?, chatList: ChatList?, isPinned: Bool?) async throws -> Ok {
        try await client.toggleChatIsPinned(
            chatId: chatId,
            chatList: chatList,
            isPinned: isPinned,
        )
    }

    func unpinChatMessage(chatId: Int64?, messageId: Int64?) async throws -> Ok {
        try await client.unpinChatMessage(chatId: chatId, messageId: messageId)
    }

    func viewMessages(
        chatId: Int64?,
        forceRead: Bool?,
        messageIds: [Int64]?,
        source: MessageSource?,
    ) async throws -> Ok {
        try await client.viewMessages(chatId: chatId, forceRead: forceRead, messageIds: messageIds, source: source)
    }
}

// MARK: - TelegramHistoryLoadingError

private enum TelegramHistoryLoadingError: LocalizedError {
    case invalidResponse
    case tdlib(code: Int, message: String)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "TDLib returned an invalid history response."
        case .tdlib(let code, let message):
            "TDLib history error \(code): \(message)"
        }
    }
}
