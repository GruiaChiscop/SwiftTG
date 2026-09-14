// FakeTelegramService.swift

@testable import BetterTG

// swiftlint:disable all
@preconcurrency import Combine
import Foundation
import Synchronization
@preconcurrency import TDLibKit

// MARK: - FakeTelegramServiceError

/// Thrown by every unimplemented `FakeTelegramService` method. `ChatVM` (and the rest of the
/// app) always calls into `TelegramService` with `try?`, so a thrown error here is silently
/// swallowed exactly like a real network failure would be - safe to use from a background
/// `Task` whose completion the test never awaits.
///
/// Conforms to `Swift.Error`, not the bare `Error`, because `TDLibKit` exports its own `Error`
/// type that shadows the standard library's once `TDLibKit` is imported.
enum FakeTelegramServiceError: Swift.Error {
    case unimplemented
}

// MARK: - FakeTelegramService

/// Mechanically generated no-op/throwing conformance to `TelegramService`, used so tests can
/// construct a real `ChatVM` (and therefore a real `ChatHistoryTableViewController`) without a
/// live TDLib connection. History requests and read receipts are recorded for regression tests; other requirements
/// throw `FakeTelegramServiceError`, do nothing, or return an empty publisher.
final class FakeTelegramService: TelegramService {
    struct ViewedMessages: Sendable {
        let chatId: Int64?
        let ids: [Int64]?
        let forceRead: Bool?
    }
    let viewedMessages = Mutex([ViewedMessages]())
    struct HistoryRequest: Sendable {
        let fromMessageId: Int64?
        let limit: Int?
    }
    let historyRequests = Mutex([HistoryRequest]())
    var authorizationStatePublisher: AnyPublisher<AuthorizationState, Never> { Empty().eraseToAnyPublisher() }
    var chatListPublisher: AnyPublisher<ChatListSnapshot, Never> { Empty().eraseToAnyPublisher() }
    var chatFoldersPublisher: AnyPublisher<UpdateChatFolders?, Never> { Empty().eraseToAnyPublisher() }
    var unreadChatCountPublisher: AnyPublisher<UpdateUnreadChatCount?, Never> { Empty().eraseToAnyPublisher() }
    var unreadMessageCountPublisher: AnyPublisher<UpdateUnreadMessageCount?, Never> { Empty().eraseToAnyPublisher() }
    var availableMessageEffectsPublisher: AnyPublisher<UpdateAvailableMessageEffects?, Never> {
        Empty().eraseToAnyPublisher()
    }

    var reactionNotificationSettingsPublisher: AnyPublisher<ReactionNotificationSettings?, Never> {
        Empty().eraseToAnyPublisher()
    }

    var updatePublisher: AnyPublisher<Update, Never> { Empty().eraseToAnyPublisher() }
    var callPublisher: AnyPublisher<Call?, Never> { Empty().eraseToAnyPublisher() }
    var callSignalingDataPublisher: AnyPublisher<UpdateNewCallSignalingData, Never> { Empty().eraseToAnyPublisher() }

    func filePublisher(fileId _: Int) -> AnyPublisher<File, Never> { Empty().eraseToAnyPublisher() }
    func messagePublisher(chatId _: Int64) -> AnyPublisher<TelegramMessageSnapshot, Never> { Empty()
        .eraseToAnyPublisher()
    }

    func mergeMessageHistory(chatId _: Int64, messages _: [Message]) {}
    func replaceMessageHistory(chatId _: Int64, messages _: [Message]) {}
    func mergeMessages(chatId _: Int64, messages _: [Message]) {}
    func mergeChatListChats(_: [Chat]) {}
    func notifyMessageContentChanged(chatId _: Int64, messageId _: Int64, newContent _: MessageContent) {}
    func addMessageReaction(
        chatId _: Int64?,
        isBig _: Bool?,
        messageId _: Int64?,
        reactionType _: ReactionType?,
        updateRecentReactions _: Bool?,
    ) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func removeMessageReaction(
        chatId _: Int64?,
        messageId _: Int64?,
        reactionType _: ReactionType?,
    ) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func addChatToList(chatId _: Int64?, chatList _: ChatList?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func cancelDownloadFile(fileId _: Int?, onlyIfPending _: Bool?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func checkAuthenticationCode(code _: String?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func checkAuthenticationEmailCode(code _: EmailAddressAuthentication?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func checkAuthenticationPassword(password _: String?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func resendAuthenticationCode() async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func requestAuthenticationPasswordRecovery() async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func recoverAuthenticationPassword(
        recoveryCode _: String?,
        newPassword _: String?,
        newHint _: String?,
    ) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func deleteAccount(reason _: String?, password _: String?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func logOut() async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func closeChat(chatId _: Int64?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func createBasicGroupChat(basicGroupId _: Int64?, force _: Bool?) async throws -> Chat {
        throw FakeTelegramServiceError.unimplemented
    }

    func createPrivateChat(force _: Bool?, userId _: Int64?) async throws -> Chat {
        throw FakeTelegramServiceError.unimplemented
    }

    func createNewSecretChat(userId _: Int64?) async throws -> Chat {
        throw FakeTelegramServiceError.unimplemented
    }

    func createSupergroupChat(force _: Bool?, supergroupId _: Int64?) async throws -> Chat {
        throw FakeTelegramServiceError.unimplemented
    }

    func createNewBasicGroupChat(
        messageAutoDeleteTime _: Int?,
        title _: String?,
        userIds _: [Int64]?,
    ) async throws -> CreatedBasicGroupChat {
        throw FakeTelegramServiceError.unimplemented
    }

    func createNewSupergroupChat(
        description _: String?,
        forImport _: Bool?,
        isChannel _: Bool?,
        isForum _: Bool?,
        location _: ChatLocation?,
        messageAutoDeleteTime _: Int?,
        title _: String?,
    ) async throws -> Chat {
        throw FakeTelegramServiceError.unimplemented
    }

    func setChatPhoto(chatId _: Int64?, photo _: InputChatPhoto?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func checkChatUsername(chatId _: Int64?, username _: String?) async throws -> CheckChatUsernameResult {
        throw FakeTelegramServiceError.unimplemented
    }

    func setSupergroupUsername(supergroupId _: Int64?, username _: String?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func deleteChat(chatId _: Int64?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func deleteChatHistory(chatId _: Int64?, removeFromChatList _: Bool?, revoke _: Bool?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func deleteMessages(chatId _: Int64?, messageIds _: [Int64]?, revoke _: Bool?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func downloadFile(
        fileId _: Int?,
        limit _: Int64?,
        offset _: Int64?,
        priority _: Int?,
        synchronous _: Bool?,
    ) async throws -> File {
        throw FakeTelegramServiceError.unimplemented
    }

    func openMessageContent(chatId _: Int64?, messageId _: Int64?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func editMessageCaption(
        caption _: FormattedText?,
        chatId _: Int64?,
        messageId _: Int64?,
        replyMarkup _: ReplyMarkup?,
        showCaptionAboveMedia _: Bool?,
    ) async throws -> Message {
        throw FakeTelegramServiceError.unimplemented
    }

    func editMessageText(
        chatId _: Int64?,
        inputMessageContent _: InputMessageContent?,
        messageId _: Int64?,
        replyMarkup _: ReplyMarkup?,
    ) async throws -> Message {
        throw FakeTelegramServiceError.unimplemented
    }

    func editMessageLiveLocation(
        chatId _: Int64?,
        location _: LiveLocation?,
        messageId _: Int64?,
        replyMarkup _: ReplyMarkup?,
    ) async throws -> Message {
        throw FakeTelegramServiceError.unimplemented
    }

    func forwardMessages(
        chatId _: Int64?,
        fromChatId _: Int64?,
        messageIds _: [Int64]?,
        options _: MessageSendOptions?,
        removeCaption _: Bool?,
        sendCopy _: Bool?,
        topicId _: MessageTopic?,
    ) async throws -> Messages {
        throw FakeTelegramServiceError.unimplemented
    }

    func getActiveLiveLocationMessages() async throws -> Messages {
        throw FakeTelegramServiceError.unimplemented
    }

    func getBasicGroup(basicGroupId _: Int64?) async throws -> BasicGroup {
        throw FakeTelegramServiceError.unimplemented
    }

    func getBasicGroupFullInfo(basicGroupId _: Int64?) async throws -> BasicGroupFullInfo {
        throw FakeTelegramServiceError.unimplemented
    }

    func getChat(chatId _: Int64?) async throws -> Chat {
        throw FakeTelegramServiceError.unimplemented
    }

    func getChatFolder(chatFolderId _: Int?) async throws -> ChatFolder {
        throw FakeTelegramServiceError.unimplemented
    }

    func createChatFolder(folder _: ChatFolder?) async throws -> ChatFolderInfo {
        throw FakeTelegramServiceError.unimplemented
    }

    func editChatFolder(chatFolderId _: Int?, folder _: ChatFolder?) async throws -> ChatFolderInfo {
        throw FakeTelegramServiceError.unimplemented
    }

    func deleteChatFolder(chatFolderId _: Int?, leaveChatIds _: [Int64]?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func getChatFolderChatsToLeave(chatFolderId _: Int?) async throws -> Chats {
        throw FakeTelegramServiceError.unimplemented
    }

    func getChatFolderChatCount(folder _: ChatFolder?) async throws -> Count {
        throw FakeTelegramServiceError.unimplemented
    }

    func reorderChatFolders(chatFolderIds _: [Int]?, mainChatListPosition _: Int?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func toggleChatFolderTags(areTagsEnabled _: Bool?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func getRecommendedChatFolders() async throws -> RecommendedChatFolders {
        throw FakeTelegramServiceError.unimplemented
    }

    func getChatFolderDefaultIconName(folder _: ChatFolder?) async throws -> ChatFolderIcon {
        throw FakeTelegramServiceError.unimplemented
    }

    func getChatScheduledMessages(chatId _: Int64?) async throws -> Messages {
        throw FakeTelegramServiceError.unimplemented
    }

    func editMessageSchedulingState(
        chatId _: Int64?,
        messageId _: Int64?,
        schedulingState _: MessageSchedulingState?,
    ) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func getChatHistory(
        chatId _: Int64?,
        fromMessageId: Int64?,
        limit: Int?,
        offset _: Int?,
        onlyLocal _: Bool?,
    ) async throws -> Messages {
        historyRequests.withLock { $0.append(HistoryRequest(fromMessageId: fromMessageId, limit: limit)) }
        return Messages(messages: [], totalCount: 0)
    }

    func getChats(chatList _: ChatList?, limit _: Int?) async throws -> Chats {
        throw FakeTelegramServiceError.unimplemented
    }

    func loadChats(chatList _: ChatList?, limit _: Int?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func getContacts() async throws -> Users {
        throw FakeTelegramServiceError.unimplemented
    }

    func addContact(contact _: ImportedContact?, sharePhoneNumber _: Bool?, userId _: Int64?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func removeContacts(userIds _: [Int64]?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func getTopChats(category _: TopChatCategory?, limit _: Int?) async throws -> Chats {
        throw FakeTelegramServiceError.unimplemented
    }

    func removeTopChat(category _: TopChatCategory?, chatId _: Int64?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func deleteSavedOrderInfo() async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func deleteSavedCredentials() async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func getAuthorizationState() async throws -> AuthorizationState {
        throw FakeTelegramServiceError.unimplemented
    }

    func getCountries() async throws -> Countries {
        throw FakeTelegramServiceError.unimplemented
    }

    func getCountryCode() async throws -> Text {
        throw FakeTelegramServiceError.unimplemented
    }

    func getGroupsInCommon(limit _: Int?, offsetChatId _: Int64?, userId _: Int64?) async throws -> Chats {
        throw FakeTelegramServiceError.unimplemented
    }

    func getStorageStatisticsFast() async throws -> StorageStatisticsFast {
        throw FakeTelegramServiceError.unimplemented
    }

    func getEmojiCategories(type _: EmojiCategoryType?) async throws -> EmojiCategories {
        throw FakeTelegramServiceError.unimplemented
    }

    func getInstalledStickerSets(stickerType _: StickerType?) async throws -> StickerSets {
        throw FakeTelegramServiceError.unimplemented
    }

    func getPremiumStickers(limit _: Int?) async throws -> Stickers {
        throw FakeTelegramServiceError.unimplemented
    }

    func getTrendingStickerSets(
        limit _: Int?,
        offset _: Int?,
        stickerType _: StickerType?,
    ) async throws -> TrendingStickerSets {
        throw FakeTelegramServiceError.unimplemented
    }

    func getMessage(chatId _: Int64?, messageId _: Int64?) async throws -> Message {
        throw FakeTelegramServiceError.unimplemented
    }

    func getMessageAvailableReactions(
        chatId _: Int64?,
        messageId _: Int64?,
        rowSize _: Int?,
    ) async throws -> AvailableReactions {
        throw FakeTelegramServiceError.unimplemented
    }

    func getMessageAddedReactions(
        chatId _: Int64?,
        limit _: Int?,
        messageId _: Int64?,
        offset _: String?,
        reactionType _: ReactionType?,
    ) async throws -> AddedReactions {
        throw FakeTelegramServiceError.unimplemented
    }

    func getMessageProperties(chatId _: Int64?, messageId _: Int64?) async throws -> MessageProperties {
        throw FakeTelegramServiceError.unimplemented
    }

    func getPollVoters(
        chatId _: Int64?,
        limit _: Int?,
        messageId _: Int64?,
        offset _: Int?,
        optionId _: Int?,
    ) async throws -> PollVoters {
        throw FakeTelegramServiceError.unimplemented
    }

    func getRecentStickers(isAttached _: Bool?) async throws -> Stickers {
        throw FakeTelegramServiceError.unimplemented
    }

    func removeRecentSticker(isAttached _: Bool?, sticker _: InputFile?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func clearRecentStickers(isAttached _: Bool?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func getFavoriteStickers() async throws -> Stickers {
        throw FakeTelegramServiceError.unimplemented
    }

    func addFavoriteSticker(sticker _: InputFile?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func removeFavoriteSticker(sticker _: InputFile?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func getActiveSessions() async throws -> Sessions {
        throw FakeTelegramServiceError.unimplemented
    }

    func terminateSession(sessionId _: TdInt64?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func confirmSession(sessionId _: TdInt64?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func terminateAllOtherSessions() async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func getStickerSet(setId _: TdInt64?) async throws -> StickerSet {
        throw FakeTelegramServiceError.unimplemented
    }

    func searchStickerSet(ignoreCache _: Bool?, name _: String?) async throws -> StickerSet {
        throw FakeTelegramServiceError.unimplemented
    }

    func getStickers(
        chatId _: Int64?,
        limit _: Int?,
        query _: String?,
        stickerType _: StickerType?,
    ) async throws -> Stickers {
        throw FakeTelegramServiceError.unimplemented
    }

    func searchStickers(
        emojis _: String?,
        inputLanguageCodes _: [String]?,
        limit _: Int?,
        offset _: Int?,
        query _: String?,
        stickerType _: StickerType?,
    ) async throws -> Stickers {
        throw FakeTelegramServiceError.unimplemented
    }

    func searchInstalledStickerSets(
        limit _: Int?,
        query _: String?,
        stickerType _: StickerType?,
    ) async throws -> StickerSets {
        throw FakeTelegramServiceError.unimplemented
    }

    func searchEmojis(inputLanguageCodes _: [String]?, text _: String?) async throws -> EmojiKeywords {
        throw FakeTelegramServiceError.unimplemented
    }

    func getSavedAnimations() async throws -> Animations {
        throw FakeTelegramServiceError.unimplemented
    }

    func addSavedAnimation(animation _: InputFile?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func removeSavedAnimation(animation _: InputFile?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func getInlineQueryResults(
        botUserId _: Int64?,
        chatId _: Int64?,
        offset _: String?,
        query _: String?,
        userLocation _: Location?,
    ) async throws -> InlineQueryResults {
        throw FakeTelegramServiceError.unimplemented
    }

    func sendInlineQueryResultMessage(
        chatId _: Int64?,
        hideViaBot _: Bool?,
        options _: MessageSendOptions?,
        queryId _: TdInt64?,
        replyTo _: InputMessageReplyTo?,
        resultId _: String?,
        topicId _: MessageTopic?,
    ) async throws -> Message {
        throw FakeTelegramServiceError.unimplemented
    }

    func uploadStickerFile(
        sticker _: InputFile?,
        stickerFormat _: StickerFormat?,
        userId _: Int64?,
    ) async throws -> File {
        throw FakeTelegramServiceError.unimplemented
    }

    func getSuggestedStickerSetName(title _: String?) async throws -> Text {
        throw FakeTelegramServiceError.unimplemented
    }

    func checkStickerSetName(name _: String?) async throws -> CheckStickerSetNameResult {
        throw FakeTelegramServiceError.unimplemented
    }

    func createNewStickerSet(
        name _: String?,
        needsRepainting _: Bool?,
        source _: String?,
        stickerType _: StickerType?,
        stickers _: [NewSticker]?,
        title _: String?,
        userId _: Int64?,
    ) async throws -> StickerSet {
        throw FakeTelegramServiceError.unimplemented
    }

    func addStickerToSet(name _: String?, sticker _: NewSticker?, userId _: Int64?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func replaceStickerInSet(
        name _: String?,
        newSticker _: NewSticker?,
        oldSticker _: InputFile?,
        userId _: Int64?,
    ) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func changeStickerSet(isArchived _: Bool?, isInstalled _: Bool?, setId _: TdInt64?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func viewTrendingStickerSets(stickerSetIds _: [TdInt64]?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func getBlockedMessageSenders(
        blockList _: BlockList?,
        limit _: Int?,
        offset _: Int?,
    ) async throws -> MessageSenders {
        throw FakeTelegramServiceError.unimplemented
    }

    func getLinkPreview(linkPreviewOptions _: LinkPreviewOptions?, text _: FormattedText?) async throws -> LinkPreview {
        throw FakeTelegramServiceError.unimplemented
    }

    func getMe() async throws -> User {
        throw FakeTelegramServiceError.unimplemented
    }

    func getMessageEffect(effectId _: TdInt64?) async throws -> MessageEffect {
        throw FakeTelegramServiceError.unimplemented
    }

    func getScopeNotificationSettings(scope _: NotificationSettingsScope?) async throws -> ScopeNotificationSettings {
        throw FakeTelegramServiceError.unimplemented
    }

    func getSupergroup(supergroupId _: Int64?) async throws -> Supergroup {
        throw FakeTelegramServiceError.unimplemented
    }

    func getSupergroupFullInfo(supergroupId _: Int64?) async throws -> SupergroupFullInfo {
        throw FakeTelegramServiceError.unimplemented
    }

    func getTextEntities(text _: String?) async throws -> TextEntities {
        throw FakeTelegramServiceError.unimplemented
    }

    func getUser(userId _: Int64?) async throws -> User {
        throw FakeTelegramServiceError.unimplemented
    }

    func translateMessageText(
        chatId _: Int64?,
        messageId _: Int64?,
        toLanguageCode _: String?,
        tone _: String?,
    ) async throws -> FormattedText {
        throw FakeTelegramServiceError.unimplemented
    }

    func importContacts(contacts _: [ImportedContact]?) async throws -> ImportedContacts {
        throw FakeTelegramServiceError.unimplemented
    }

    func getUserFullInfo(userId _: Int64?) async throws -> UserFullInfo {
        throw FakeTelegramServiceError.unimplemented
    }

    func getSupergroupMembers(
        filter _: SupergroupMembersFilter?,
        limit _: Int?,
        offset _: Int?,
        supergroupId _: Int64?,
    ) async throws -> ChatMembers {
        throw FakeTelegramServiceError.unimplemented
    }

    func leaveChat(chatId _: Int64?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func joinChat(chatId _: Int64?) async throws -> ChatJoinResult {
        throw FakeTelegramServiceError.unimplemented
    }

    func openChat(chatId _: Int64?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func pinChatMessage(
        chatId _: Int64?,
        disableNotification _: Bool?,
        messageId _: Int64?,
        onlyForSelf _: Bool?,
    ) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func processPushNotification(payload _: String?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func preliminaryUploadFile(file _: InputFile?, fileType _: FileType?, priority _: Int?) async throws -> File {
        throw FakeTelegramServiceError.unimplemented
    }

    func cancelPreliminaryUploadFile(fileId _: Int?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func registerDevice(deviceToken _: DeviceToken?, otherUserIds _: [Int64]?) async throws -> PushReceiverId {
        throw FakeTelegramServiceError.unimplemented
    }

    func sendChatAction(
        action _: ChatAction?,
        businessConnectionId _: String?,
        chatId _: Int64?,
        topicId _: MessageTopic?,
    ) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func sendMessage(
        chatId _: Int64?,
        inputMessageContent _: InputMessageContent?,
        options _: MessageSendOptions?,
        replyMarkup _: ReplyMarkup?,
        replyTo _: InputMessageReplyTo?,
        topicId _: MessageTopic?,
    ) async throws -> Message {
        throw FakeTelegramServiceError.unimplemented
    }

    func sendMessageAlbum(
        chatId _: Int64?,
        inputMessageContents _: [InputMessageContent]?,
        options _: MessageSendOptions?,
        replyTo _: InputMessageReplyTo?,
        topicId _: MessageTopic?,
    ) async throws -> Messages {
        throw FakeTelegramServiceError.unimplemented
    }

    func getMessageThread(chatId _: Int64?, messageId _: Int64?) async throws -> MessageThreadInfo {
        throw FakeTelegramServiceError.unimplemented
    }

    func getMessageThreadHistory(
        chatId _: Int64?,
        fromMessageId _: Int64?,
        limit _: Int?,
        messageId _: Int64?,
        offset _: Int?,
    ) async throws -> Messages {
        throw FakeTelegramServiceError.unimplemented
    }

    func getForumTopics(
        chatId _: Int64?,
        limit _: Int?,
        offsetDate _: Int?,
        offsetForumTopicId _: Int?,
        offsetMessageId _: Int64?,
        query _: String?,
    ) async throws -> ForumTopics {
        throw FakeTelegramServiceError.unimplemented
    }

    func getForumTopic(chatId _: Int64?, forumTopicId _: Int?) async throws -> ForumTopic {
        throw FakeTelegramServiceError.unimplemented
    }

    func getForumTopicHistory(
        chatId _: Int64?,
        forumTopicId _: Int?,
        fromMessageId _: Int64?,
        limit _: Int?,
        offset _: Int?,
    ) async throws -> Messages {
        throw FakeTelegramServiceError.unimplemented
    }

    func createForumTopic(
        chatId _: Int64?,
        icon _: ForumTopicIcon?,
        isNameImplicit _: Bool?,
        name _: String?,
    ) async throws -> ForumTopicInfo {
        throw FakeTelegramServiceError.unimplemented
    }

    func editForumTopic(
        chatId _: Int64?,
        editIconCustomEmoji _: Bool?,
        forumTopicId _: Int?,
        iconCustomEmojiId _: TdInt64?,
        name _: String?,
    ) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func deleteForumTopic(chatId _: Int64?, forumTopicId _: Int?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func toggleForumTopicIsClosed(chatId _: Int64?, forumTopicId _: Int?, isClosed _: Bool?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func toggleForumTopicIsPinned(chatId _: Int64?, forumTopicId _: Int?, isPinned _: Bool?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func setForumTopicNotificationSettings(
        chatId _: Int64?,
        forumTopicId _: Int?,
        notificationSettings _: ChatNotificationSettings?,
    ) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func getForumTopicDefaultIcons() async throws -> Stickers {
        throw FakeTelegramServiceError.unimplemented
    }

    func searchChats(limit _: Int?, query _: String?, typeFilter _: SearchChatTypeFilter?) async throws -> Chats {
        throw FakeTelegramServiceError.unimplemented
    }

    func searchPublicChats(query _: String?, typeFilter _: SearchChatTypeFilter?) async throws -> Chats {
        throw FakeTelegramServiceError.unimplemented
    }

    func searchChatMembers(
        chatId _: Int64?,
        filter _: ChatMembersFilter?,
        limit _: Int?,
        query _: String?,
    ) async throws -> ChatMembers {
        throw FakeTelegramServiceError.unimplemented
    }

    func searchChatMessages(
        chatId _: Int64?,
        filter _: SearchMessagesFilter?,
        fromMessageId _: Int64?,
        limit _: Int?,
        offset _: Int?,
        query _: String?,
        senderId _: MessageSender?,
        topicId _: MessageTopic?,
    ) async throws -> FoundChatMessages {
        throw FakeTelegramServiceError.unimplemented
    }

    func searchCallMessages(limit _: Int?, offset _: String?, onlyMissed _: Bool?) async throws -> FoundMessages {
        throw FakeTelegramServiceError.unimplemented
    }

    func searchMessages(
        chatList _: ChatList?,
        chatTypeFilter _: SearchMessagesChatTypeFilter?,
        filter _: SearchMessagesFilter?,
        limit _: Int?,
        maxDate _: Int?,
        minDate _: Int?,
        offset _: String?,
        query _: String?,
    ) async throws -> FoundMessages {
        throw FakeTelegramServiceError.unimplemented
    }

    func searchSecretMessages(
        chatId _: Int64?,
        filter _: SearchMessagesFilter?,
        limit _: Int?,
        offset _: String?,
        query _: String?,
    ) async throws -> FoundMessages {
        throw FakeTelegramServiceError.unimplemented
    }

    func deleteAllCallMessages(revoke _: Bool?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func setChatNotificationSettings(
        chatId _: Int64?,
        notificationSettings _: ChatNotificationSettings?,
    ) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func setChatDraftMessage(
        chatId _: Int64?,
        draftMessage _: DraftMessage?,
        topicId _: MessageTopic?,
    ) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func setAuthenticationPhoneNumber(
        phoneNumber _: String?,
        settings _: PhoneNumberAuthenticationSettings?,
    ) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func setAuthenticationEmailAddress(emailAddress _: String?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func registerUser(disableNotification _: Bool?, firstName _: String?, lastName _: String?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func requestQrCodeAuthentication(otherUserIds _: [Int64]?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func confirmQrCodeAuthentication(link _: String?) async throws -> Session {
        throw FakeTelegramServiceError.unimplemented
    }

    func setMessageSenderBlockList(blockList _: BlockList?, senderId _: MessageSender?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func reportChat(
        chatId _: Int64?,
        messageIds _: [Int64]?,
        optionId _: Data?,
        text _: String?,
    ) async throws -> ReportChatResult {
        throw FakeTelegramServiceError.unimplemented
    }

    func getUserPrivacySettingRules(setting _: UserPrivacySetting?) async throws -> UserPrivacySettingRules {
        throw FakeTelegramServiceError.unimplemented
    }

    func setUserPrivacySettingRules(
        rules _: UserPrivacySettingRules?,
        setting _: UserPrivacySetting?,
    ) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func getConnectedWebsites() async throws -> ConnectedWebsites {
        throw FakeTelegramServiceError.unimplemented
    }

    func disconnectWebsite(websiteId _: TdInt64?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func disconnectAllWebsites() async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func getAccountTtl() async throws -> AccountTtl {
        throw FakeTelegramServiceError.unimplemented
    }

    func setAccountTtl(ttl _: AccountTtl?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func getArchiveChatListSettings() async throws -> ArchiveChatListSettings {
        throw FakeTelegramServiceError.unimplemented
    }

    func setArchiveChatListSettings(settings _: ArchiveChatListSettings?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func getLoginPasskeys() async throws -> Passkeys {
        throw FakeTelegramServiceError.unimplemented
    }

    func removeLoginPasskey(passkeyId _: String?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func getNewChatPrivacySettings() async throws -> NewChatPrivacySettings {
        throw FakeTelegramServiceError.unimplemented
    }

    func setNewChatPrivacySettings(settings _: NewChatPrivacySettings?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func setScopeNotificationSettings(
        notificationSettings _: ScopeNotificationSettings?,
        scope _: NotificationSettingsScope?,
    ) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func setReactionNotificationSettings(notificationSettings _: ReactionNotificationSettings?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func resetAllNotificationSettings() async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func getSavedNotificationSounds() async throws -> NotificationSounds {
        throw FakeTelegramServiceError.unimplemented
    }

    func getSavedNotificationSound(notificationSoundId _: TdInt64?) async throws -> NotificationSound {
        throw FakeTelegramServiceError.unimplemented
    }

    func addSavedNotificationSound(sound _: InputFile?) async throws -> NotificationSound {
        throw FakeTelegramServiceError.unimplemented
    }

    func removeSavedNotificationSound(notificationSoundId _: TdInt64?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func getAutoDownloadSettingsPresets() async throws -> AutoDownloadSettingsPresets {
        throw FakeTelegramServiceError.unimplemented
    }

    func setAutoDownloadSettings(settings _: AutoDownloadSettings?, type _: NetworkType?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func getPasswordState() async throws -> PasswordState {
        throw FakeTelegramServiceError.unimplemented
    }

    func getRecoveryEmailAddress(password _: String?) async throws -> RecoveryEmailAddress {
        throw FakeTelegramServiceError.unimplemented
    }

    func setPassword(
        newHint _: String?,
        newPassword _: String?,
        newRecoveryEmailAddress _: String?,
        oldPassword _: String?,
        setRecoveryEmailAddress _: Bool?,
    ) async throws -> PasswordState {
        throw FakeTelegramServiceError.unimplemented
    }

    func checkRecoveryEmailAddressCode(code _: String?) async throws -> PasswordState {
        throw FakeTelegramServiceError.unimplemented
    }

    func resendRecoveryEmailAddressCode() async throws -> PasswordState {
        throw FakeTelegramServiceError.unimplemented
    }

    func cancelRecoveryEmailAddressVerification() async throws -> PasswordState {
        throw FakeTelegramServiceError.unimplemented
    }

    func addProxy(comment _: String?, enable _: Bool?, proxy _: Proxy?) async throws -> AddedProxy {
        throw FakeTelegramServiceError.unimplemented
    }

    func editProxy(comment _: String?, enable _: Bool?, proxy _: Proxy?, proxyId _: Int?) async throws -> AddedProxy {
        throw FakeTelegramServiceError.unimplemented
    }

    func enableProxy(proxyId _: Int?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func disableProxy() async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func removeProxy(proxyId _: Int?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func getProxies() async throws -> AddedProxies {
        throw FakeTelegramServiceError.unimplemented
    }

    func pingProxy(proxy _: Proxy?) async throws -> Seconds {
        throw FakeTelegramServiceError.unimplemented
    }

    func getInternalLinkType(link _: String?) async throws -> InternalLinkType {
        throw FakeTelegramServiceError.unimplemented
    }

    func getMessageLinkInfo(url _: String?) async throws -> MessageLinkInfo {
        throw FakeTelegramServiceError.unimplemented
    }

    func searchPublicChat(username _: String?) async throws -> Chat {
        throw FakeTelegramServiceError.unimplemented
    }

    func checkChatInviteLink(inviteLink _: String?) async throws -> ChatInviteLinkInfo {
        throw FakeTelegramServiceError.unimplemented
    }

    func joinChatByInviteLink(inviteLink _: String?) async throws -> ChatJoinResult {
        throw FakeTelegramServiceError.unimplemented
    }

    func searchUserByPhoneNumber(onlyLocal _: Bool?, phoneNumber _: String?) async throws -> User {
        throw FakeTelegramServiceError.unimplemented
    }

    func sendBotStartMessage(botUserId _: Int64?, chatId _: Int64?, parameter _: String?) async throws -> Message {
        throw FakeTelegramServiceError.unimplemented
    }

    func setName(firstName _: String?, lastName _: String?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func setBio(bio _: String?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func setUsername(username _: String?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func setProfilePhoto(isPublic _: Bool?, photo _: InputChatPhoto?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func setOption(name _: String?, value _: OptionValue?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func getOption(name _: String?) async throws -> OptionValue {
        throw FakeTelegramServiceError.unimplemented
    }

    func getApplicationConfig() async throws -> JsonValue {
        throw FakeTelegramServiceError.unimplemented
    }

    func getAutosaveSettings() async throws -> AutosaveSettings {
        throw FakeTelegramServiceError.unimplemented
    }

    func setAutosaveSettings(scope _: AutosaveSettingsScope?, settings _: ScopeAutosaveSettings?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func getDefaultMessageAutoDeleteTime() async throws -> MessageAutoDeleteTime {
        throw FakeTelegramServiceError.unimplemented
    }

    func setDefaultMessageAutoDeleteTime(messageAutoDeleteTime _: MessageAutoDeleteTime?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func setChatMessageAutoDeleteTime(chatId _: Int64?, messageAutoDeleteTime _: Int?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func setPollAnswer(chatId _: Int64?, messageId _: Int64?, optionIds _: [Int]?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func markChecklistTasksAsDone(
        chatId _: Int64?,
        markedAsDoneTaskIds _: [Int]?,
        markedAsNotDoneTaskIds _: [Int]?,
        messageId _: Int64?,
    ) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func toggleChatIsMarkedAsUnread(chatId _: Int64?, isMarkedAsUnread _: Bool?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func toggleChatIsPinned(chatId _: Int64?, chatList _: ChatList?, isPinned _: Bool?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func unpinChatMessage(chatId _: Int64?, messageId _: Int64?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func viewMessages(
        chatId: Int64?,
        forceRead: Bool?,
        messageIds: [Int64]?,
        source _: MessageSource?,
    ) async throws -> Ok {
        viewedMessages.withLock { $0.append(ViewedMessages(chatId: chatId, ids: messageIds, forceRead: forceRead)) }
        return Ok()
    }

    func optimizeStorage(
        chatIds _: [Int64]?,
        chatLimit _: Int?,
        count _: Int?,
        excludeChatIds _: [Int64]?,
        fileTypes _: [FileType]?,
        immunityDelay _: Int?,
        returnDeletedFileStatistics _: Bool?,
        size _: Int64?,
        ttl _: Int?,
    ) async throws -> StorageStatistics {
        throw FakeTelegramServiceError.unimplemented
    }

    func createCall(isVideo _: Bool?, protocol _: CallProtocol?, userId _: Int64?) async throws -> CallId {
        throw FakeTelegramServiceError.unimplemented
    }

    func acceptCall(callId _: Int?, protocol _: CallProtocol?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func discardCall(
        callId _: Int?,
        connectionId _: TdInt64?,
        duration _: Int?,
        inviteLink _: String?,
        isDisconnected _: Bool?,
        isVideo _: Bool?,
    ) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func sendCallSignalingData(callId _: Int?, data _: Data?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func sendCallDebugInformation(callId _: Int?, debugInformation _: String?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func sendCallLog(callId _: Int?, path _: String) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func sendCallRating(
        callId _: Int?,
        comment _: String?,
        problems _: [TelegramCallRatingProblem]?,
        rating _: Int?,
    ) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func createGroupCall(joinParameters _: GroupCallJoinParameters?) async throws -> GroupCallInfo {
        throw FakeTelegramServiceError.unimplemented
    }

    func createVideoChat(
        chatId _: Int64?,
        isRtmpStream _: Bool?,
        startDate _: Int?,
        title _: String?,
    ) async throws -> GroupCallId {
        throw FakeTelegramServiceError.unimplemented
    }

    func joinGroupCall(
        inputGroupCall _: InputGroupCall?,
        joinParameters _: GroupCallJoinParameters?,
    ) async throws -> GroupCallInfo {
        throw FakeTelegramServiceError.unimplemented
    }

    func joinVideoChat(
        groupCallId _: Int?,
        inviteHash _: String?,
        joinParameters _: GroupCallJoinParameters?,
        participantId _: MessageSender?,
    ) async throws -> Text {
        throw FakeTelegramServiceError.unimplemented
    }

    func getVideoChatAvailableParticipants(chatId _: Int64?) async throws -> MessageSenders {
        throw FakeTelegramServiceError.unimplemented
    }

    func setVideoChatDefaultParticipant(chatId _: Int64?, defaultParticipantId _: MessageSender?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func getGroupCallStreams(groupCallId _: Int?) async throws -> GroupCallStreams {
        throw FakeTelegramServiceError.unimplemented
    }

    func getGroupCallStreamSegment(
        channelId _: Int?,
        groupCallId _: Int?,
        scale _: Int?,
        timeOffset _: Int64?,
        videoQuality _: GroupCallVideoQuality?,
    ) async throws -> TdData {
        throw FakeTelegramServiceError.unimplemented
    }

    func startScheduledVideoChat(groupCallId _: Int?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func toggleVideoChatEnabledStartNotification(
        enabledStartNotification _: Bool?,
        groupCallId _: Int?,
    ) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func getVideoChatInviteLink(canSelfUnmute _: Bool?, groupCallId _: Int?) async throws -> HttpUrl {
        throw FakeTelegramServiceError.unimplemented
    }

    func inviteVideoChatParticipants(groupCallId _: Int?, userIds _: [Int64]?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func revokeGroupCallInviteLink(groupCallId _: Int?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func setVideoChatTitle(groupCallId _: Int?, title _: String?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func toggleVideoChatMuteNewParticipants(groupCallId _: Int?, muteNewParticipants _: Bool?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func toggleGroupCallAreMessagesAllowed(areMessagesAllowed _: Bool?, groupCallId _: Int?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func startGroupCallRecording(
        groupCallId _: Int?,
        recordVideo _: Bool?,
        title _: String?,
        usePortraitOrientation _: Bool?,
    ) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func endGroupCallRecording(groupCallId _: Int?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func getVideoChatRtmpUrl(chatId _: Int64?) async throws -> RtmpUrl {
        throw FakeTelegramServiceError.unimplemented
    }

    func replaceVideoChatRtmpUrl(chatId _: Int64?) async throws -> RtmpUrl {
        throw FakeTelegramServiceError.unimplemented
    }

    func startGroupCallScreenSharing(
        audioSourceId _: Int?,
        groupCallId _: Int?,
        payload _: String?,
    ) async throws -> Text {
        throw FakeTelegramServiceError.unimplemented
    }

    func endGroupCallScreenSharing(groupCallId _: Int?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func getGroupCall(groupCallId _: Int?) async throws -> GroupCall {
        throw FakeTelegramServiceError.unimplemented
    }

    func getGroupCallParticipants(
        inputGroupCall _: InputGroupCall?,
        limit _: Int?,
    ) async throws -> GroupCallParticipants {
        throw FakeTelegramServiceError.unimplemented
    }

    func inviteGroupCallParticipant(
        groupCallId _: Int?,
        isVideo _: Bool?,
        userId _: Int64?,
    ) async throws -> InviteGroupCallParticipantResult {
        throw FakeTelegramServiceError.unimplemented
    }

    func declineGroupCallInvitation(chatId _: Int64?, messageId _: Int64?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func toggleGroupCallParticipantIsMuted(
        groupCallId _: Int?,
        isMuted _: Bool?,
        participantId _: MessageSender?,
    ) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func toggleGroupCallParticipantIsHandRaised(
        groupCallId _: Int?,
        isHandRaised _: Bool?,
        participantId _: MessageSender?,
    ) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func setGroupCallParticipantVolumeLevel(
        groupCallId _: Int?,
        participantId _: MessageSender?,
        volumeLevel _: Int?,
    ) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func banGroupCallParticipants(groupCallId _: Int?, userIds _: [TdInt64]?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func loadGroupCallParticipants(groupCallId _: Int?, limit _: Int?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func sendGroupCallMessage(
        groupCallId _: Int?,
        paidMessageStarCount _: Int64?,
        text _: FormattedText?,
    ) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func encryptGroupCallData(
        data _: Data?,
        dataChannel _: GroupCallDataChannel?,
        groupCallId _: Int?,
        unencryptedPrefixSize _: Int?,
    ) async throws -> TdData {
        throw FakeTelegramServiceError.unimplemented
    }

    func encryptGroupCallData(
        data _: Data,
        dataChannel _: GroupCallDataChannel,
        groupCallId _: Int,
        unencryptedPrefixSize _: Int,
        completion: @escaping @Sendable (Data?) -> Void,
    ) {
        completion(nil)
    }

    func decryptGroupCallData(
        data _: Data?,
        dataChannel _: GroupCallDataChannel?,
        groupCallId _: Int?,
        participantId _: MessageSender?,
    ) async throws -> TdData {
        throw FakeTelegramServiceError.unimplemented
    }

    func decryptGroupCallData(
        data _: Data,
        dataChannel _: GroupCallDataChannel?,
        groupCallId _: Int,
        participantId _: MessageSender,
        completion: @escaping @Sendable (Data?) -> Void,
    ) {
        completion(nil)
    }

    func leaveGroupCall(groupCallId _: Int?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func endGroupCall(groupCallId _: Int?) async throws -> Ok {
        throw FakeTelegramServiceError.unimplemented
    }

    func changeImportedContacts(contacts _: [ImportedContact]?) async throws -> ImportedContacts {
        throw FakeTelegramServiceError.unimplemented
    }
}
