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
    var chatFoldersPublisher: AnyPublisher<UpdateChatFolders?, Never> { get }
    var unreadChatCountPublisher: AnyPublisher<UpdateUnreadChatCount?, Never> { get }
    var availableMessageEffectsPublisher: AnyPublisher<UpdateAvailableMessageEffects?, Never> { get }
    var reactionNotificationSettingsPublisher: AnyPublisher<ReactionNotificationSettings?, Never> { get }
    var updatePublisher: AnyPublisher<Update, Never> { get }
    var callPublisher: AnyPublisher<Call?, Never> { get }
    var callSignalingDataPublisher: AnyPublisher<UpdateNewCallSignalingData, Never> { get }

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
    func checkAuthenticationEmailCode(code: EmailAddressAuthentication?) async throws -> Ok
    func checkAuthenticationPassword(password: String?) async throws -> Ok
    func requestAuthenticationPasswordRecovery() async throws -> Ok
    func recoverAuthenticationPassword(recoveryCode: String?, newPassword: String?, newHint: String?) async throws -> Ok
    func deleteAccount(reason: String?, password: String?) async throws -> Ok
    func closeChat(chatId: Int64?) async throws -> Ok
    func createBasicGroupChat(basicGroupId: Int64?, force: Bool?) async throws -> Chat
    func createPrivateChat(force: Bool?, userId: Int64?) async throws -> Chat
    func createNewSecretChat(userId: Int64?) async throws -> Chat
    func createSupergroupChat(force: Bool?, supergroupId: Int64?) async throws -> Chat
    func createNewBasicGroupChat(
        messageAutoDeleteTime: Int?,
        title: String?,
        userIds: [Int64]?,
    ) async throws -> CreatedBasicGroupChat
    func createNewSupergroupChat(
        description: String?,
        forImport: Bool?,
        isChannel: Bool?,
        isForum: Bool?,
        location: ChatLocation?,
        messageAutoDeleteTime: Int?,
        title: String?,
    ) async throws -> Chat
    func setChatPhoto(chatId: Int64?, photo: InputChatPhoto?) async throws -> Ok
    func checkChatUsername(chatId: Int64?, username: String?) async throws -> CheckChatUsernameResult
    func setSupergroupUsername(supergroupId: Int64?, username: String?) async throws -> Ok
    func deleteChat(chatId: Int64?) async throws -> Ok
    func deleteChatHistory(chatId: Int64?, removeFromChatList: Bool?, revoke: Bool?) async throws -> Ok
    func deleteMessages(chatId: Int64?, messageIds: [Int64]?, revoke: Bool?) async throws -> Ok
    func downloadFile(fileId: Int?, limit: Int64?, offset: Int64?, priority: Int?, synchronous: Bool?) async throws
        -> File
    func openMessageContent(chatId: Int64?, messageId: Int64?) async throws -> Ok
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
    /// `location: nil` stops sharing the live location.
    func editMessageLiveLocation(
        chatId: Int64?,
        location: LiveLocation?,
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
    /// Every outgoing live location that still needs periodic updates - persisted by TDLib across
    /// app restarts, so this is how tracking resumes after a relaunch.
    func getActiveLiveLocationMessages() async throws -> Messages
    func getBasicGroup(basicGroupId: Int64?) async throws -> BasicGroup
    func getBasicGroupFullInfo(basicGroupId: Int64?) async throws -> BasicGroupFullInfo
    func getChat(chatId: Int64?) async throws -> Chat
    func getChatFolder(chatFolderId: Int?) async throws -> ChatFolder
    func createChatFolder(folder: ChatFolder?) async throws -> ChatFolderInfo
    func editChatFolder(chatFolderId: Int?, folder: ChatFolder?) async throws -> ChatFolderInfo
    func deleteChatFolder(chatFolderId: Int?, leaveChatIds: [Int64]?) async throws -> Ok
    func getChatFolderChatsToLeave(chatFolderId: Int?) async throws -> Chats
    func getChatFolderChatCount(folder: ChatFolder?) async throws -> Count
    func reorderChatFolders(chatFolderIds: [Int]?, mainChatListPosition: Int?) async throws -> Ok
    func toggleChatFolderTags(areTagsEnabled: Bool?) async throws -> Ok
    func getRecommendedChatFolders() async throws -> RecommendedChatFolders
    func getChatFolderDefaultIconName(folder: ChatFolder?) async throws -> ChatFolderIcon
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
    func loadChats(chatList: ChatList?, limit: Int?) async throws -> Ok
    func getContacts() async throws -> Users
    func removeContacts(userIds: [Int64]?) async throws -> Ok
    func getTopChats(category: TopChatCategory?, limit: Int?) async throws -> Chats
    func removeTopChat(category: TopChatCategory?, chatId: Int64?) async throws -> Ok
    func deleteSavedOrderInfo() async throws -> Ok
    func deleteSavedCredentials() async throws -> Ok
    func getAuthorizationState() async throws -> AuthorizationState
    func getCountries() async throws -> Countries
    func getCountryCode() async throws -> Text
    func getGroupsInCommon(limit: Int?, offsetChatId: Int64?, userId: Int64?) async throws -> Chats
    func getStorageStatisticsFast() async throws -> StorageStatisticsFast
    func getEmojiCategories(type: EmojiCategoryType?) async throws -> EmojiCategories
    func getInstalledStickerSets(stickerType: StickerType?) async throws -> StickerSets
    func getPremiumStickers(limit: Int?) async throws -> Stickers
    func getTrendingStickerSets(limit: Int?, offset: Int?, stickerType: StickerType?) async throws
        -> TrendingStickerSets
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
    func removeRecentSticker(isAttached: Bool?, sticker: InputFile?) async throws -> Ok
    func clearRecentStickers(isAttached: Bool?) async throws -> Ok
    func getFavoriteStickers() async throws -> Stickers
    func addFavoriteSticker(sticker: InputFile?) async throws -> Ok
    func removeFavoriteSticker(sticker: InputFile?) async throws -> Ok
    func getActiveSessions() async throws -> Sessions
    func terminateSession(sessionId: TdInt64?) async throws -> Ok
    func confirmSession(sessionId: TdInt64?) async throws -> Ok
    func terminateAllOtherSessions() async throws -> Ok
    func getStickerSet(setId: TdInt64?) async throws -> StickerSet
    func searchStickerSet(ignoreCache: Bool?, name: String?) async throws -> StickerSet
    func getStickers(
        chatId: Int64?,
        limit: Int?,
        query: String?,
        stickerType: StickerType?,
    ) async throws -> Stickers
    /// Searches the public sticker catalog, not just installed sets - unlike `getStickers`, which
    /// only ever returns stickers from sets the user already has.
    func searchStickers(
        emojis: String?,
        inputLanguageCodes: [String]?,
        limit: Int?,
        offset: Int?,
        query: String?,
        stickerType: StickerType?,
    ) async throws -> Stickers
    func searchInstalledStickerSets(limit: Int?, query: String?, stickerType: StickerType?) async throws -> StickerSets
    /// `searchStickers` is fundamentally emoji-driven ("stickers... that correspond to any of the
    /// given emoji") - real Telegram clients resolve a typed keyword to emoji with this call first,
    /// the same way this app's own catalog sticker search needs to.
    func searchEmojis(inputLanguageCodes: [String]?, text: String?) async throws -> EmojiKeywords
    func getSavedAnimations() async throws -> Animations
    func addSavedAnimation(animation: InputFile?) async throws -> Ok
    func removeSavedAnimation(animation: InputFile?) async throws -> Ok
    /// Queries an inline bot (e.g. Telegram's own GIF-search bot, whose username comes from
    /// `getOption("animation_search_bot_username")`) the same way real Telegram clients back GIF
    /// search - TDLib has no direct "search GIFs" call of its own.
    func getInlineQueryResults(
        botUserId: Int64?,
        chatId: Int64?,
        offset: String?,
        query: String?,
        userLocation: Location?,
    ) async throws -> InlineQueryResults
    func sendInlineQueryResultMessage(
        chatId: Int64?,
        hideViaBot: Bool?,
        options: MessageSendOptions?,
        queryId: TdInt64?,
        replyTo: InputMessageReplyTo?,
        resultId: String?,
        topicId: MessageTopic?,
    ) async throws -> Message
    func uploadStickerFile(sticker: InputFile?, stickerFormat: StickerFormat?, userId: Int64?) async throws -> File
    func getSuggestedStickerSetName(title: String?) async throws -> Text
    func checkStickerSetName(name: String?) async throws -> CheckStickerSetNameResult
    func createNewStickerSet(
        name: String?,
        needsRepainting: Bool?,
        source: String?,
        stickerType: StickerType?,
        stickers: [NewSticker]?,
        title: String?,
        userId: Int64?,
    ) async throws -> StickerSet
    func addStickerToSet(name: String?, sticker: NewSticker?, userId: Int64?) async throws -> Ok
    func replaceStickerInSet(
        name: String?,
        newSticker: NewSticker?,
        oldSticker: InputFile?,
        userId: Int64?,
    ) async throws -> Ok
    func changeStickerSet(isArchived: Bool?, isInstalled: Bool?, setId: TdInt64?) async throws -> Ok
    func viewTrendingStickerSets(stickerSetIds: [TdInt64]?) async throws -> Ok
    func getBlockedMessageSenders(blockList: BlockList?, limit: Int?, offset: Int?) async throws -> MessageSenders
    func getLinkPreview(linkPreviewOptions: LinkPreviewOptions?, text: FormattedText?) async throws -> LinkPreview
    func getMe() async throws -> User
    func getMessageEffect(effectId: TdInt64?) async throws -> MessageEffect
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
    func joinChat(chatId: Int64?) async throws -> ChatJoinResult
    func openChat(chatId: Int64?) async throws -> Ok
    func pinChatMessage(chatId: Int64?, disableNotification: Bool?, messageId: Int64?, onlyForSelf: Bool?) async throws
        -> Ok
    func processPushNotification(payload: String?) async throws -> Ok
    func preliminaryUploadFile(file: InputFile?, fileType: FileType?, priority: Int?) async throws -> File
    func cancelPreliminaryUploadFile(fileId: Int?) async throws -> Ok
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
    func getMessageThread(chatId: Int64?, messageId: Int64?) async throws -> MessageThreadInfo
    func getMessageThreadHistory(
        chatId: Int64?,
        fromMessageId: Int64?,
        limit: Int?,
        messageId: Int64?,
        offset: Int?,
    ) async throws -> Messages
    func getForumTopics(
        chatId: Int64?,
        limit: Int?,
        offsetDate: Int?,
        offsetForumTopicId: Int?,
        offsetMessageId: Int64?,
        query: String?,
    ) async throws -> ForumTopics
    func getForumTopic(chatId: Int64?, forumTopicId: Int?) async throws -> ForumTopic
    func getForumTopicHistory(
        chatId: Int64?,
        forumTopicId: Int?,
        fromMessageId: Int64?,
        limit: Int?,
        offset: Int?,
    ) async throws -> Messages
    func createForumTopic(
        chatId: Int64?,
        icon: ForumTopicIcon?,
        isNameImplicit: Bool?,
        name: String?,
    ) async throws -> ForumTopicInfo
    func editForumTopic(
        chatId: Int64?,
        editIconCustomEmoji: Bool?,
        forumTopicId: Int?,
        iconCustomEmojiId: TdInt64?,
        name: String?,
    ) async throws -> Ok
    func deleteForumTopic(chatId: Int64?, forumTopicId: Int?) async throws -> Ok
    func toggleForumTopicIsClosed(chatId: Int64?, forumTopicId: Int?, isClosed: Bool?) async throws -> Ok
    func toggleForumTopicIsPinned(chatId: Int64?, forumTopicId: Int?, isPinned: Bool?) async throws -> Ok
    func setForumTopicNotificationSettings(
        chatId: Int64?,
        forumTopicId: Int?,
        notificationSettings: ChatNotificationSettings?,
    ) async throws -> Ok
    func getForumTopicDefaultIcons() async throws -> Stickers
    func searchChats(limit: Int?, query: String?, typeFilter: SearchChatTypeFilter?) async throws -> Chats
    func searchPublicChats(query: String?, typeFilter: SearchChatTypeFilter?) async throws -> Chats
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
    func searchCallMessages(limit: Int?, offset: String?, onlyMissed: Bool?) async throws -> FoundMessages
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
    func deleteAllCallMessages(revoke: Bool?) async throws -> Ok
    func setChatNotificationSettings(chatId: Int64?, notificationSettings: ChatNotificationSettings?) async throws -> Ok
    func setChatDraftMessage(chatId: Int64?, draftMessage: DraftMessage?, topicId: MessageTopic?) async throws -> Ok
    func setAuthenticationPhoneNumber(
        phoneNumber: String?,
        settings: PhoneNumberAuthenticationSettings?,
    ) async throws -> Ok
    func setAuthenticationEmailAddress(emailAddress: String?) async throws -> Ok
    func registerUser(disableNotification: Bool?, firstName: String?, lastName: String?) async throws -> Ok
    func requestQrCodeAuthentication(otherUserIds: [Int64]?) async throws -> Ok
    /// Approves a login QR code scanned with the in-app camera on another (already logged-in)
    /// device - the counterpart to `requestQrCodeAuthentication`, which is what generates the
    /// code being scanned in the first place.
    func confirmQrCodeAuthentication(link: String?) async throws -> Session
    func setMessageSenderBlockList(blockList: BlockList?, senderId: MessageSender?) async throws -> Ok
    func getUserPrivacySettingRules(setting: UserPrivacySetting?) async throws -> UserPrivacySettingRules
    func setUserPrivacySettingRules(rules: UserPrivacySettingRules?, setting: UserPrivacySetting?) async throws -> Ok
    func getConnectedWebsites() async throws -> ConnectedWebsites
    func disconnectWebsite(websiteId: TdInt64?) async throws -> Ok
    func disconnectAllWebsites() async throws -> Ok
    func getAccountTtl() async throws -> AccountTtl
    func setAccountTtl(ttl: AccountTtl?) async throws -> Ok
    func getArchiveChatListSettings() async throws -> ArchiveChatListSettings
    func setArchiveChatListSettings(settings: ArchiveChatListSettings?) async throws -> Ok
    func getLoginPasskeys() async throws -> Passkeys
    func removeLoginPasskey(passkeyId: String?) async throws -> Ok
    func getNewChatPrivacySettings() async throws -> NewChatPrivacySettings
    func setNewChatPrivacySettings(settings: NewChatPrivacySettings?) async throws -> Ok
    func setScopeNotificationSettings(
        notificationSettings: ScopeNotificationSettings?,
        scope: NotificationSettingsScope?,
    ) async throws -> Ok
    func setReactionNotificationSettings(notificationSettings: ReactionNotificationSettings?) async throws -> Ok
    func resetAllNotificationSettings() async throws -> Ok
    func getSavedNotificationSounds() async throws -> NotificationSounds
    func getSavedNotificationSound(notificationSoundId: TdInt64?) async throws -> NotificationSound
    func addSavedNotificationSound(sound: InputFile?) async throws -> NotificationSound
    func removeSavedNotificationSound(notificationSoundId: TdInt64?) async throws -> Ok
    func getAutoDownloadSettingsPresets() async throws -> AutoDownloadSettingsPresets
    func setAutoDownloadSettings(settings: AutoDownloadSettings?, type: NetworkType?) async throws -> Ok
    func getPasswordState() async throws -> PasswordState
    func getRecoveryEmailAddress(password: String?) async throws -> RecoveryEmailAddress
    func setPassword(
        newHint: String?,
        newPassword: String?,
        newRecoveryEmailAddress: String?,
        oldPassword: String?,
        setRecoveryEmailAddress: Bool?,
    ) async throws -> PasswordState
    func checkRecoveryEmailAddressCode(code: String?) async throws -> PasswordState
    func resendRecoveryEmailAddressCode() async throws -> PasswordState
    func cancelRecoveryEmailAddressVerification() async throws -> PasswordState
    func addProxy(comment: String?, enable: Bool?, proxy: Proxy?) async throws -> AddedProxy
    func editProxy(comment: String?, enable: Bool?, proxy: Proxy?, proxyId: Int?) async throws -> AddedProxy
    func enableProxy(proxyId: Int?) async throws -> Ok
    func disableProxy() async throws -> Ok
    func removeProxy(proxyId: Int?) async throws -> Ok
    func getProxies() async throws -> AddedProxies
    func pingProxy(proxy: Proxy?) async throws -> Seconds
    func getInternalLinkType(link: String?) async throws -> InternalLinkType
    func getMessageLinkInfo(url: String?) async throws -> MessageLinkInfo
    func searchPublicChat(username: String?) async throws -> Chat
    func checkChatInviteLink(inviteLink: String?) async throws -> ChatInviteLinkInfo
    func joinChatByInviteLink(inviteLink: String?) async throws -> ChatJoinResult
    func searchUserByPhoneNumber(onlyLocal: Bool?, phoneNumber: String?) async throws -> User
    func sendBotStartMessage(botUserId: Int64?, chatId: Int64?, parameter: String?) async throws -> Message
    func setName(firstName: String?, lastName: String?) async throws -> Ok
    func setBio(bio: String?) async throws -> Ok
    func setUsername(username: String?) async throws -> Ok
    func setProfilePhoto(isPublic: Bool?, photo: InputChatPhoto?) async throws -> Ok
    func setOption(name: String?, value: OptionValue?) async throws -> Ok
    func getOption(name: String?) async throws -> OptionValue
    func getApplicationConfig() async throws -> JsonValue
    func getAutosaveSettings() async throws -> AutosaveSettings
    func setAutosaveSettings(scope: AutosaveSettingsScope?, settings: ScopeAutosaveSettings?) async throws -> Ok
    func getDefaultMessageAutoDeleteTime() async throws -> MessageAutoDeleteTime
    func setDefaultMessageAutoDeleteTime(messageAutoDeleteTime: MessageAutoDeleteTime?) async throws -> Ok
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

    func createCall(isVideo: Bool?, protocol: CallProtocol?, userId: Int64?) async throws -> CallId
    func acceptCall(callId: Int?, protocol: CallProtocol?) async throws -> Ok
    func discardCall(
        callId: Int?,
        connectionId: TdInt64?,
        duration: Int?,
        inviteLink: String?,
        isDisconnected: Bool?,
        isVideo: Bool?,
    ) async throws -> Ok
    func sendCallSignalingData(callId: Int?, data: Data?) async throws -> Ok
    func sendCallDebugInformation(callId: Int?, debugInformation: String?) async throws -> Ok
    func sendCallLog(callId: Int?, path: String) async throws -> Ok
    func sendCallRating(
        callId: Int?,
        comment: String?,
        problems: [TelegramCallRatingProblem]?,
        rating: Int?,
    ) async throws -> Ok

    func createGroupCall(joinParameters: GroupCallJoinParameters?) async throws -> GroupCallInfo
    func createVideoChat(
        chatId: Int64?,
        isRtmpStream: Bool?,
        startDate: Int?,
        title: String?,
    ) async throws -> GroupCallId
    func joinGroupCall(
        inputGroupCall: InputGroupCall?,
        joinParameters: GroupCallJoinParameters?,
    ) async throws -> GroupCallInfo
    func joinVideoChat(
        groupCallId: Int?,
        inviteHash: String?,
        joinParameters: GroupCallJoinParameters?,
        participantId: MessageSender?,
    ) async throws -> Text
    func getVideoChatAvailableParticipants(chatId: Int64?) async throws -> MessageSenders
    func setVideoChatDefaultParticipant(chatId: Int64?, defaultParticipantId: MessageSender?) async throws -> Ok
    func getGroupCallStreams(groupCallId: Int?) async throws -> GroupCallStreams
    func getGroupCallStreamSegment(
        channelId: Int?,
        groupCallId: Int?,
        scale: Int?,
        timeOffset: Int64?,
        videoQuality: GroupCallVideoQuality?,
    ) async throws -> TdData
    func startScheduledVideoChat(groupCallId: Int?) async throws -> Ok
    func toggleVideoChatEnabledStartNotification(
        enabledStartNotification: Bool?,
        groupCallId: Int?,
    ) async throws -> Ok
    func getVideoChatInviteLink(canSelfUnmute: Bool?, groupCallId: Int?) async throws -> HttpUrl
    func inviteVideoChatParticipants(groupCallId: Int?, userIds: [Int64]?) async throws -> Ok
    func revokeGroupCallInviteLink(groupCallId: Int?) async throws -> Ok
    func setVideoChatTitle(groupCallId: Int?, title: String?) async throws -> Ok
    func toggleVideoChatMuteNewParticipants(groupCallId: Int?, muteNewParticipants: Bool?) async throws -> Ok
    func toggleGroupCallAreMessagesAllowed(areMessagesAllowed: Bool?, groupCallId: Int?) async throws -> Ok
    func startGroupCallRecording(
        groupCallId: Int?,
        recordVideo: Bool?,
        title: String?,
        usePortraitOrientation: Bool?,
    ) async throws -> Ok
    func endGroupCallRecording(groupCallId: Int?) async throws -> Ok
    func getVideoChatRtmpUrl(chatId: Int64?) async throws -> RtmpUrl
    func replaceVideoChatRtmpUrl(chatId: Int64?) async throws -> RtmpUrl
    func startGroupCallScreenSharing(
        audioSourceId: Int?,
        groupCallId: Int?,
        payload: String?,
    ) async throws -> Text
    func endGroupCallScreenSharing(groupCallId: Int?) async throws -> Ok
    func getGroupCall(groupCallId: Int?) async throws -> GroupCall
    func getGroupCallParticipants(
        inputGroupCall: InputGroupCall?,
        limit: Int?,
    ) async throws -> GroupCallParticipants
    func inviteGroupCallParticipant(
        groupCallId: Int?,
        isVideo: Bool?,
        userId: Int64?,
    ) async throws -> InviteGroupCallParticipantResult
    func declineGroupCallInvitation(chatId: Int64?, messageId: Int64?) async throws -> Ok
    func toggleGroupCallParticipantIsMuted(
        groupCallId: Int?,
        isMuted: Bool?,
        participantId: MessageSender?,
    ) async throws -> Ok
    func toggleGroupCallParticipantIsHandRaised(
        groupCallId: Int?,
        isHandRaised: Bool?,
        participantId: MessageSender?,
    ) async throws -> Ok
    func setGroupCallParticipantVolumeLevel(
        groupCallId: Int?,
        participantId: MessageSender?,
        volumeLevel: Int?,
    ) async throws -> Ok
    func banGroupCallParticipants(groupCallId: Int?, userIds: [TdInt64]?) async throws -> Ok
    func loadGroupCallParticipants(groupCallId: Int?, limit: Int?) async throws -> Ok
    func sendGroupCallMessage(
        groupCallId: Int?,
        paidMessageStarCount: Int64?,
        text: FormattedText?,
    ) async throws -> Ok
    func encryptGroupCallData(
        data: Data?,
        dataChannel: GroupCallDataChannel?,
        groupCallId: Int?,
        unencryptedPrefixSize: Int?,
    ) async throws -> TdData
    func encryptGroupCallData(
        data: Data,
        dataChannel: GroupCallDataChannel,
        groupCallId: Int,
        unencryptedPrefixSize: Int,
        completion: @escaping @Sendable (Data?) -> Void,
    )
    func decryptGroupCallData(
        data: Data?,
        dataChannel: GroupCallDataChannel?,
        groupCallId: Int?,
        participantId: MessageSender?,
    ) async throws -> TdData
    func decryptGroupCallData(
        data: Data,
        dataChannel: GroupCallDataChannel?,
        groupCallId: Int,
        participantId: MessageSender,
        completion: @escaping @Sendable (Data?) -> Void,
    )
    func leaveGroupCall(groupCallId: Int?) async throws -> Ok
    func endGroupCall(groupCallId: Int?) async throws -> Ok
}

// MARK: - TelegramSession + TelegramService

extension TelegramSession: TelegramService {
    func getStorageStatisticsFast() async throws -> StorageStatisticsFast {
        try await client.getStorageStatisticsFast()
    }

    func setOption(name: String?, value: OptionValue?) async throws -> Ok {
        try await client.setOption(name: name, value: value)
    }

    func getOption(name: String?) async throws -> OptionValue {
        try await client.getOption(name: name)
    }

    func getApplicationConfig() async throws -> JsonValue {
        try await client.getApplicationConfig()
    }

    func getAutosaveSettings() async throws -> AutosaveSettings {
        try await client.getAutosaveSettings()
    }

    func setAutosaveSettings(scope: AutosaveSettingsScope?, settings: ScopeAutosaveSettings?) async throws -> Ok {
        try await client.setAutosaveSettings(scope: scope, settings: settings)
    }

    func getDefaultMessageAutoDeleteTime() async throws -> MessageAutoDeleteTime {
        try await client.getDefaultMessageAutoDeleteTime()
    }

    func setDefaultMessageAutoDeleteTime(messageAutoDeleteTime: MessageAutoDeleteTime?) async throws -> Ok {
        try await client.setDefaultMessageAutoDeleteTime(messageAutoDeleteTime: messageAutoDeleteTime)
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

    func preliminaryUploadFile(file: InputFile?, fileType: FileType?, priority: Int?) async throws -> File {
        try await client.preliminaryUploadFile(file: file, fileType: fileType, priority: priority)
    }

    func cancelPreliminaryUploadFile(fileId: Int?) async throws -> Ok {
        try await client.cancelPreliminaryUploadFile(fileId: fileId)
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

    func removeContacts(userIds: [Int64]?) async throws -> Ok {
        try await client.removeContacts(userIds: userIds)
    }

    func getTopChats(category: TopChatCategory?, limit: Int?) async throws -> Chats {
        try await client.getTopChats(category: category, limit: limit)
    }

    func removeTopChat(category: TopChatCategory?, chatId: Int64?) async throws -> Ok {
        try await client.removeTopChat(category: category, chatId: chatId)
    }

    func deleteSavedOrderInfo() async throws -> Ok {
        try await client.deleteSavedOrderInfo()
    }

    func deleteSavedCredentials() async throws -> Ok {
        try await client.deleteSavedCredentials()
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

    func createNewBasicGroupChat(
        messageAutoDeleteTime: Int?,
        title: String?,
        userIds: [Int64]?,
    ) async throws -> CreatedBasicGroupChat {
        try await client.createNewBasicGroupChat(
            messageAutoDeleteTime: messageAutoDeleteTime,
            title: title,
            userIds: userIds,
        )
    }

    func createNewSupergroupChat(
        description: String?,
        forImport: Bool?,
        isChannel: Bool?,
        isForum: Bool?,
        location: ChatLocation?,
        messageAutoDeleteTime: Int?,
        title: String?,
    ) async throws -> Chat {
        try await client.createNewSupergroupChat(
            description: description,
            forImport: forImport,
            isChannel: isChannel,
            isForum: isForum,
            location: location,
            messageAutoDeleteTime: messageAutoDeleteTime,
            title: title,
        )
    }

    func setChatPhoto(chatId: Int64?, photo: InputChatPhoto?) async throws -> Ok {
        try await client.setChatPhoto(chatId: chatId, photo: photo)
    }

    func checkChatUsername(chatId: Int64?, username: String?) async throws -> CheckChatUsernameResult {
        try await client.checkChatUsername(chatId: chatId, username: username)
    }

    func setSupergroupUsername(supergroupId: Int64?, username: String?) async throws -> Ok {
        try await client.setSupergroupUsername(supergroupId: supergroupId, username: username)
    }

    func deleteChat(chatId: Int64?) async throws -> Ok {
        try await client.deleteChat(chatId: chatId)
    }

    func searchChats(limit: Int?, query: String?, typeFilter: SearchChatTypeFilter?) async throws -> Chats {
        try await client.searchChats(limit: limit, query: query, typeFilter: typeFilter)
    }

    func searchPublicChats(query: String?, typeFilter: SearchChatTypeFilter?) async throws -> Chats {
        try await client.searchPublicChats(query: query, typeFilter: typeFilter)
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

    func searchCallMessages(limit: Int?, offset: String?, onlyMissed: Bool?) async throws -> FoundMessages {
        try await client.searchCallMessages(limit: limit, offset: offset, onlyMissed: onlyMissed)
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

    func deleteAllCallMessages(revoke: Bool?) async throws -> Ok {
        try await client.deleteAllCallMessages(revoke: revoke)
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

    func checkAuthenticationEmailCode(code: EmailAddressAuthentication?) async throws -> Ok {
        try await client.checkAuthenticationEmailCode(code: code)
    }

    func checkAuthenticationPassword(password: String?) async throws -> Ok {
        try await client.checkAuthenticationPassword(password: password)
    }

    func requestAuthenticationPasswordRecovery() async throws -> Ok {
        try await client.requestAuthenticationPasswordRecovery()
    }

    func recoverAuthenticationPassword(
        recoveryCode: String?,
        newPassword: String?,
        newHint: String?,
    ) async throws -> Ok {
        try await client.recoverAuthenticationPassword(
            newHint: newHint,
            newPassword: newPassword,
            recoveryCode: recoveryCode,
        )
    }

    func deleteAccount(reason: String?, password: String?) async throws -> Ok {
        try await client.deleteAccount(password: password, reason: reason)
    }

    func closeChat(chatId: Int64?) async throws -> Ok {
        try await client.closeChat(chatId: chatId)
    }

    func createPrivateChat(force: Bool?, userId: Int64?) async throws -> Chat {
        try await client.createPrivateChat(force: force, userId: userId)
    }

    func createNewSecretChat(userId: Int64?) async throws -> Chat {
        try await client.createNewSecretChat(userId: userId)
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

    func openMessageContent(chatId: Int64?, messageId: Int64?) async throws -> Ok {
        try await client.openMessageContent(chatId: chatId, messageId: messageId)
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

    func editMessageLiveLocation(
        chatId: Int64?,
        location: LiveLocation?,
        messageId: Int64?,
        replyMarkup: ReplyMarkup?,
    ) async throws -> Message {
        try await client.editMessageLiveLocation(
            chatId: chatId,
            location: location,
            messageId: messageId,
            replyMarkup: replyMarkup,
        )
    }

    /// `GetActiveLiveLocationMessages` exists as a TDLibKit model but was never wired into either
    /// of TDLibKit's generated client classes (`TDLibApi`/`TdApi`) - confirmed against the
    /// upstream repo, not just this checkout, via `gh api search/code`, and the currently pinned
    /// commit is the newest one touching that generated file, so bumping the package wouldn't add
    /// it either. This replicates what the generated wrappers' own private `run(query:)` does,
    /// using the same public building blocks it uses internally (`client.encoder`/`client.decoder`
    /// are `public let`, already configured with TDLib's snake_case wire format) - except for
    /// unwrapping the response, since `DTO.payload` is only `internal` from outside the module:
    /// TDLib's response JSON carries the payload's own fields directly (just tagged with an
    /// `@type`/`@extra` envelope Codable's keyed decoding ignores unless asked for it), so
    /// decoding straight into `Error`/`Messages` themselves - skipping `DTO<...>` on this side -
    /// works the same as unwrapping `.payload` would have.
    func getActiveLiveLocationMessages() async throws -> Messages {
        try await withCheckedThrowingContinuation { continuation in
            do {
                let dto = DTO(GetActiveLiveLocationMessages(), encoder: client.encoder)
                try client.send(query: dto) { [self] data in
                    if let error = try? client.decoder.decode(TDLibKit.Error.self, from: data) {
                        continuation.resume(throwing: error)
                    } else if let response = try? client.decoder.decode(Messages.self, from: data) {
                        continuation.resume(returning: response)
                    } else {
                        continuation.resume(throwing: TDLibKit.Error(
                            code: 500,
                            message: "Couldn't decode getActiveLiveLocationMessages response",
                        ))
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
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

    func createChatFolder(folder: ChatFolder?) async throws -> ChatFolderInfo {
        try await client.createChatFolder(folder: folder)
    }

    func editChatFolder(chatFolderId: Int?, folder: ChatFolder?) async throws -> ChatFolderInfo {
        try await client.editChatFolder(chatFolderId: chatFolderId, folder: folder)
    }

    func deleteChatFolder(chatFolderId: Int?, leaveChatIds: [Int64]?) async throws -> Ok {
        try await client.deleteChatFolder(chatFolderId: chatFolderId, leaveChatIds: leaveChatIds)
    }

    func getChatFolderChatsToLeave(chatFolderId: Int?) async throws -> Chats {
        try await client.getChatFolderChatsToLeave(chatFolderId: chatFolderId)
    }

    func getChatFolderChatCount(folder: ChatFolder?) async throws -> Count {
        try await client.getChatFolderChatCount(folder: folder)
    }

    func reorderChatFolders(chatFolderIds: [Int]?, mainChatListPosition: Int?) async throws -> Ok {
        try await client.reorderChatFolders(chatFolderIds: chatFolderIds, mainChatListPosition: mainChatListPosition)
    }

    func toggleChatFolderTags(areTagsEnabled: Bool?) async throws -> Ok {
        try await client.toggleChatFolderTags(areTagsEnabled: areTagsEnabled)
    }

    func getRecommendedChatFolders() async throws -> RecommendedChatFolders {
        try await client.getRecommendedChatFolders()
    }

    func getChatFolderDefaultIconName(folder: ChatFolder?) async throws -> ChatFolderIcon {
        try await client.getChatFolderDefaultIconName(folder: folder)
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

    func loadChats(chatList: ChatList?, limit: Int?) async throws -> Ok {
        try await client.loadChats(chatList: chatList, limit: limit)
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

    func getEmojiCategories(type: EmojiCategoryType?) async throws -> EmojiCategories {
        try await client.getEmojiCategories(type: type)
    }

    func getPremiumStickers(limit: Int?) async throws -> Stickers {
        try await client.getPremiumStickers(limit: limit)
    }

    func getTrendingStickerSets(
        limit: Int?,
        offset: Int?,
        stickerType: StickerType?,
    ) async throws -> TrendingStickerSets {
        try await client.getTrendingStickerSets(limit: limit, offset: offset, stickerType: stickerType)
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

    func removeRecentSticker(isAttached: Bool?, sticker: InputFile?) async throws -> Ok {
        try await client.removeRecentSticker(isAttached: isAttached, sticker: sticker)
    }

    func clearRecentStickers(isAttached: Bool?) async throws -> Ok {
        try await client.clearRecentStickers(isAttached: isAttached)
    }

    func getFavoriteStickers() async throws -> Stickers {
        try await client.getFavoriteStickers()
    }

    func addFavoriteSticker(sticker: InputFile?) async throws -> Ok {
        try await client.addFavoriteSticker(sticker: sticker)
    }

    func removeFavoriteSticker(sticker: InputFile?) async throws -> Ok {
        try await client.removeFavoriteSticker(sticker: sticker)
    }

    func getActiveSessions() async throws -> Sessions {
        try await client.getActiveSessions()
    }

    func terminateSession(sessionId: TdInt64?) async throws -> Ok {
        try await client.terminateSession(sessionId: sessionId)
    }

    func confirmSession(sessionId: TdInt64?) async throws -> Ok {
        try await client.confirmSession(sessionId: sessionId)
    }

    func terminateAllOtherSessions() async throws -> Ok {
        try await client.terminateAllOtherSessions()
    }

    func getStickerSet(setId: TdInt64?) async throws -> StickerSet {
        try await client.getStickerSet(setId: setId)
    }

    func searchStickerSet(ignoreCache: Bool?, name: String?) async throws -> StickerSet {
        try await client.searchStickerSet(ignoreCache: ignoreCache, name: name)
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

    func searchStickers(
        emojis: String?,
        inputLanguageCodes: [String]?,
        limit: Int?,
        offset: Int?,
        query: String?,
        stickerType: StickerType?,
    ) async throws -> Stickers {
        try await client.searchStickers(
            emojis: emojis,
            inputLanguageCodes: inputLanguageCodes,
            limit: limit,
            offset: offset,
            query: query,
            stickerType: stickerType,
        )
    }

    func searchInstalledStickerSets(
        limit: Int?,
        query: String?,
        stickerType: StickerType?,
    ) async throws -> StickerSets {
        try await client.searchInstalledStickerSets(limit: limit, query: query, stickerType: stickerType)
    }

    func searchEmojis(inputLanguageCodes: [String]?, text: String?) async throws -> EmojiKeywords {
        try await client.searchEmojis(inputLanguageCodes: inputLanguageCodes, text: text)
    }

    func getSavedAnimations() async throws -> Animations {
        try await client.getSavedAnimations()
    }

    func addSavedAnimation(animation: InputFile?) async throws -> Ok {
        try await client.addSavedAnimation(animation: animation)
    }

    func removeSavedAnimation(animation: InputFile?) async throws -> Ok {
        try await client.removeSavedAnimation(animation: animation)
    }

    func getInlineQueryResults(
        botUserId: Int64?,
        chatId: Int64?,
        offset: String?,
        query: String?,
        userLocation: Location?,
    ) async throws -> InlineQueryResults {
        try await client.getInlineQueryResults(
            botUserId: botUserId,
            chatId: chatId,
            offset: offset,
            query: query,
            userLocation: userLocation,
        )
    }

    func sendInlineQueryResultMessage(
        chatId: Int64?,
        hideViaBot: Bool?,
        options: MessageSendOptions?,
        queryId: TdInt64?,
        replyTo: InputMessageReplyTo?,
        resultId: String?,
        topicId: MessageTopic?,
    ) async throws -> Message {
        try await client.sendInlineQueryResultMessage(
            chatId: chatId,
            hideViaBot: hideViaBot,
            options: options,
            queryId: queryId,
            replyTo: replyTo,
            resultId: resultId,
            topicId: topicId,
        )
    }

    func uploadStickerFile(sticker: InputFile?, stickerFormat: StickerFormat?, userId: Int64?) async throws -> File {
        try await client.uploadStickerFile(sticker: sticker, stickerFormat: stickerFormat, userId: userId)
    }

    func getSuggestedStickerSetName(title: String?) async throws -> Text {
        try await client.getSuggestedStickerSetName(title: title)
    }

    func checkStickerSetName(name: String?) async throws -> CheckStickerSetNameResult {
        try await client.checkStickerSetName(name: name)
    }

    func createNewStickerSet(
        name: String?,
        needsRepainting: Bool?,
        source: String?,
        stickerType: StickerType?,
        stickers: [NewSticker]?,
        title: String?,
        userId: Int64?,
    ) async throws -> StickerSet {
        try await client.createNewStickerSet(
            name: name,
            needsRepainting: needsRepainting,
            source: source,
            stickerType: stickerType,
            stickers: stickers,
            title: title,
            userId: userId,
        )
    }

    func addStickerToSet(name: String?, sticker: NewSticker?, userId: Int64?) async throws -> Ok {
        try await client.addStickerToSet(name: name, sticker: sticker, userId: userId)
    }

    func replaceStickerInSet(
        name: String?,
        newSticker: NewSticker?,
        oldSticker: InputFile?,
        userId: Int64?,
    ) async throws -> Ok {
        try await client.replaceStickerInSet(
            name: name,
            newSticker: newSticker,
            oldSticker: oldSticker,
            userId: userId,
        )
    }

    func changeStickerSet(isArchived: Bool?, isInstalled: Bool?, setId: TdInt64?) async throws -> Ok {
        try await client.changeStickerSet(isArchived: isArchived, isInstalled: isInstalled, setId: setId)
    }

    func viewTrendingStickerSets(stickerSetIds: [TdInt64]?) async throws -> Ok {
        try await client.viewTrendingStickerSets(stickerSetIds: stickerSetIds)
    }

    func getBlockedMessageSenders(blockList: BlockList?, limit: Int?, offset: Int?) async throws -> MessageSenders {
        try await client.getBlockedMessageSenders(blockList: blockList, limit: limit, offset: offset)
    }

    func getLinkPreview(linkPreviewOptions: LinkPreviewOptions?, text: FormattedText?) async throws -> LinkPreview {
        try await client.getLinkPreview(linkPreviewOptions: linkPreviewOptions, text: text)
    }

    func getMe() async throws -> User {
        try await client.getMe()
    }

    func getMessageEffect(effectId: TdInt64?) async throws -> MessageEffect {
        try await client.getMessageEffect(effectId: effectId)
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

    func joinChat(chatId: Int64?) async throws -> ChatJoinResult {
        try await client.joinChat(chatId: chatId)
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

    func getMessageThread(chatId: Int64?, messageId: Int64?) async throws -> MessageThreadInfo {
        try await client.getMessageThread(chatId: chatId, messageId: messageId)
    }

    func getMessageThreadHistory(
        chatId: Int64?,
        fromMessageId: Int64?,
        limit: Int?,
        messageId: Int64?,
        offset: Int?,
    ) async throws -> Messages {
        try await client.getMessageThreadHistory(
            chatId: chatId,
            fromMessageId: fromMessageId,
            limit: limit,
            messageId: messageId,
            offset: offset,
        )
    }

    func getForumTopics(
        chatId: Int64?,
        limit: Int?,
        offsetDate: Int?,
        offsetForumTopicId: Int?,
        offsetMessageId: Int64?,
        query: String?,
    ) async throws -> ForumTopics {
        try await client.getForumTopics(
            chatId: chatId,
            limit: limit,
            offsetDate: offsetDate,
            offsetForumTopicId: offsetForumTopicId,
            offsetMessageId: offsetMessageId,
            query: query,
        )
    }

    func getForumTopic(chatId: Int64?, forumTopicId: Int?) async throws -> ForumTopic {
        try await client.getForumTopic(chatId: chatId, forumTopicId: forumTopicId)
    }

    func getForumTopicHistory(
        chatId: Int64?,
        forumTopicId: Int?,
        fromMessageId: Int64?,
        limit: Int?,
        offset: Int?,
    ) async throws -> Messages {
        try await client.getForumTopicHistory(
            chatId: chatId,
            forumTopicId: forumTopicId,
            fromMessageId: fromMessageId,
            limit: limit,
            offset: offset,
        )
    }

    func createForumTopic(
        chatId: Int64?,
        icon: ForumTopicIcon?,
        isNameImplicit: Bool?,
        name: String?,
    ) async throws -> ForumTopicInfo {
        try await client.createForumTopic(chatId: chatId, icon: icon, isNameImplicit: isNameImplicit, name: name)
    }

    func editForumTopic(
        chatId: Int64?,
        editIconCustomEmoji: Bool?,
        forumTopicId: Int?,
        iconCustomEmojiId: TdInt64?,
        name: String?,
    ) async throws -> Ok {
        try await client.editForumTopic(
            chatId: chatId,
            editIconCustomEmoji: editIconCustomEmoji,
            forumTopicId: forumTopicId,
            iconCustomEmojiId: iconCustomEmojiId,
            name: name,
        )
    }

    func deleteForumTopic(chatId: Int64?, forumTopicId: Int?) async throws -> Ok {
        try await client.deleteForumTopic(chatId: chatId, forumTopicId: forumTopicId)
    }

    func toggleForumTopicIsClosed(chatId: Int64?, forumTopicId: Int?, isClosed: Bool?) async throws -> Ok {
        try await client.toggleForumTopicIsClosed(chatId: chatId, forumTopicId: forumTopicId, isClosed: isClosed)
    }

    func toggleForumTopicIsPinned(chatId: Int64?, forumTopicId: Int?, isPinned: Bool?) async throws -> Ok {
        try await client.toggleForumTopicIsPinned(chatId: chatId, forumTopicId: forumTopicId, isPinned: isPinned)
    }

    func setForumTopicNotificationSettings(
        chatId: Int64?,
        forumTopicId: Int?,
        notificationSettings: ChatNotificationSettings?,
    ) async throws -> Ok {
        try await client.setForumTopicNotificationSettings(
            chatId: chatId,
            forumTopicId: forumTopicId,
            notificationSettings: notificationSettings,
        )
    }

    func getForumTopicDefaultIcons() async throws -> Stickers {
        try await client.getForumTopicDefaultIcons()
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

    func getUserPrivacySettingRules(setting: UserPrivacySetting?) async throws -> UserPrivacySettingRules {
        try await client.getUserPrivacySettingRules(setting: setting)
    }

    func setUserPrivacySettingRules(rules: UserPrivacySettingRules?, setting: UserPrivacySetting?) async throws -> Ok {
        try await client.setUserPrivacySettingRules(rules: rules, setting: setting)
    }

    func getConnectedWebsites() async throws -> ConnectedWebsites {
        try await client.getConnectedWebsites()
    }

    func disconnectWebsite(websiteId: TdInt64?) async throws -> Ok {
        try await client.disconnectWebsite(websiteId: websiteId)
    }

    func disconnectAllWebsites() async throws -> Ok {
        try await client.disconnectAllWebsites()
    }

    func getAccountTtl() async throws -> AccountTtl {
        try await client.getAccountTtl()
    }

    func setAccountTtl(ttl: AccountTtl?) async throws -> Ok {
        try await client.setAccountTtl(ttl: ttl)
    }

    func getArchiveChatListSettings() async throws -> ArchiveChatListSettings {
        try await client.getArchiveChatListSettings()
    }

    func setArchiveChatListSettings(settings: ArchiveChatListSettings?) async throws -> Ok {
        try await client.setArchiveChatListSettings(settings: settings)
    }

    func getLoginPasskeys() async throws -> Passkeys {
        try await client.getLoginPasskeys()
    }

    func removeLoginPasskey(passkeyId: String?) async throws -> Ok {
        try await client.removeLoginPasskey(passkeyId: passkeyId)
    }

    func getNewChatPrivacySettings() async throws -> NewChatPrivacySettings {
        try await client.getNewChatPrivacySettings()
    }

    func setNewChatPrivacySettings(settings: NewChatPrivacySettings?) async throws -> Ok {
        try await client.setNewChatPrivacySettings(settings: settings)
    }

    func setScopeNotificationSettings(
        notificationSettings: ScopeNotificationSettings?,
        scope: NotificationSettingsScope?,
    ) async throws -> Ok {
        try await client.setScopeNotificationSettings(notificationSettings: notificationSettings, scope: scope)
    }

    func setReactionNotificationSettings(notificationSettings: ReactionNotificationSettings?) async throws -> Ok {
        try await client.setReactionNotificationSettings(notificationSettings: notificationSettings)
    }

    func resetAllNotificationSettings() async throws -> Ok {
        try await client.resetAllNotificationSettings()
    }

    func getSavedNotificationSounds() async throws -> NotificationSounds {
        try await client.getSavedNotificationSounds()
    }

    func getSavedNotificationSound(notificationSoundId: TdInt64?) async throws -> NotificationSound {
        try await client.getSavedNotificationSound(notificationSoundId: notificationSoundId)
    }

    func addSavedNotificationSound(sound: InputFile?) async throws -> NotificationSound {
        try await client.addSavedNotificationSound(sound: sound)
    }

    func removeSavedNotificationSound(notificationSoundId: TdInt64?) async throws -> Ok {
        try await client.removeSavedNotificationSound(notificationSoundId: notificationSoundId)
    }

    func getAutoDownloadSettingsPresets() async throws -> AutoDownloadSettingsPresets {
        try await client.getAutoDownloadSettingsPresets()
    }

    func setAutoDownloadSettings(settings: AutoDownloadSettings?, type: NetworkType?) async throws -> Ok {
        try await client.setAutoDownloadSettings(settings: settings, type: type)
    }

    func getPasswordState() async throws -> PasswordState {
        try await client.getPasswordState()
    }

    func getRecoveryEmailAddress(password: String?) async throws -> RecoveryEmailAddress {
        try await client.getRecoveryEmailAddress(password: password)
    }

    func setPassword(
        newHint: String?,
        newPassword: String?,
        newRecoveryEmailAddress: String?,
        oldPassword: String?,
        setRecoveryEmailAddress: Bool?,
    ) async throws -> PasswordState {
        try await client.setPassword(
            newHint: newHint,
            newPassword: newPassword,
            newRecoveryEmailAddress: newRecoveryEmailAddress,
            oldPassword: oldPassword,
            setRecoveryEmailAddress: setRecoveryEmailAddress,
        )
    }

    func checkRecoveryEmailAddressCode(code: String?) async throws -> PasswordState {
        try await client.checkRecoveryEmailAddressCode(code: code)
    }

    func resendRecoveryEmailAddressCode() async throws -> PasswordState {
        try await client.resendRecoveryEmailAddressCode()
    }

    func cancelRecoveryEmailAddressVerification() async throws -> PasswordState {
        try await client.cancelRecoveryEmailAddressVerification()
    }

    func addProxy(comment: String?, enable: Bool?, proxy: Proxy?) async throws -> AddedProxy {
        try await client.addProxy(comment: comment, enable: enable, proxy: proxy)
    }

    func editProxy(comment: String?, enable: Bool?, proxy: Proxy?, proxyId: Int?) async throws -> AddedProxy {
        try await client.editProxy(comment: comment, enable: enable, proxy: proxy, proxyId: proxyId)
    }

    func enableProxy(proxyId: Int?) async throws -> Ok {
        try await client.enableProxy(proxyId: proxyId)
    }

    func disableProxy() async throws -> Ok {
        try await client.disableProxy()
    }

    func removeProxy(proxyId: Int?) async throws -> Ok {
        try await client.removeProxy(proxyId: proxyId)
    }

    func getProxies() async throws -> AddedProxies {
        try await client.getProxies()
    }

    func pingProxy(proxy: Proxy?) async throws -> Seconds {
        try await client.pingProxy(proxy: proxy)
    }

    func getInternalLinkType(link: String?) async throws -> InternalLinkType {
        try await client.getInternalLinkType(link: link)
    }

    func getMessageLinkInfo(url: String?) async throws -> MessageLinkInfo {
        try await client.getMessageLinkInfo(url: url)
    }

    func searchPublicChat(username: String?) async throws -> Chat {
        try await client.searchPublicChat(username: username)
    }

    func checkChatInviteLink(inviteLink: String?) async throws -> ChatInviteLinkInfo {
        try await client.checkChatInviteLink(inviteLink: inviteLink)
    }

    func joinChatByInviteLink(inviteLink: String?) async throws -> ChatJoinResult {
        try await client.joinChatByInviteLink(inviteLink: inviteLink)
    }

    func searchUserByPhoneNumber(onlyLocal: Bool?, phoneNumber: String?) async throws -> User {
        try await client.searchUserByPhoneNumber(onlyLocal: onlyLocal, phoneNumber: phoneNumber)
    }

    func sendBotStartMessage(botUserId: Int64?, chatId: Int64?, parameter: String?) async throws -> Message {
        try await client.sendBotStartMessage(botUserId: botUserId, chatId: chatId, parameter: parameter)
    }

    func setName(firstName: String?, lastName: String?) async throws -> Ok {
        try await client.setName(firstName: firstName, lastName: lastName)
    }

    func setBio(bio: String?) async throws -> Ok {
        try await client.setBio(bio: bio)
    }

    func setUsername(username: String?) async throws -> Ok {
        try await client.setUsername(username: username)
    }

    func setProfilePhoto(isPublic: Bool?, photo: InputChatPhoto?) async throws -> Ok {
        try await client.setProfilePhoto(isPublic: isPublic, photo: photo)
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

    func setAuthenticationEmailAddress(emailAddress: String?) async throws -> Ok {
        try await client.setAuthenticationEmailAddress(emailAddress: emailAddress)
    }

    func registerUser(disableNotification: Bool?, firstName: String?, lastName: String?) async throws -> Ok {
        try await client.registerUser(
            disableNotification: disableNotification,
            firstName: firstName,
            lastName: lastName,
        )
    }

    func requestQrCodeAuthentication(otherUserIds: [Int64]?) async throws -> Ok {
        try await client.requestQrCodeAuthentication(otherUserIds: otherUserIds)
    }

    func confirmQrCodeAuthentication(link: String?) async throws -> Session {
        try await client.confirmQrCodeAuthentication(link: link)
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

    func createCall(isVideo: Bool?, protocol: CallProtocol?, userId: Int64?) async throws -> CallId {
        try await client.createCall(isVideo: isVideo, protocol: `protocol`, userId: userId)
    }

    func acceptCall(callId: Int?, protocol: CallProtocol?) async throws -> Ok {
        try await client.acceptCall(callId: callId, protocol: `protocol`)
    }

    func discardCall(
        callId: Int?,
        connectionId: TdInt64?,
        duration: Int?,
        inviteLink: String?,
        isDisconnected: Bool?,
        isVideo: Bool?,
    ) async throws -> Ok {
        try await client.discardCall(
            callId: callId,
            connectionId: connectionId,
            duration: duration,
            inviteLink: inviteLink,
            isDisconnected: isDisconnected,
            isVideo: isVideo,
        )
    }

    func sendCallSignalingData(callId: Int?, data: Data?) async throws -> Ok {
        try await client.sendCallSignalingData(callId: callId, data: data)
    }

    func sendCallDebugInformation(callId: Int?, debugInformation: String?) async throws -> Ok {
        try await client.sendCallDebugInformation(
            callId: callId.map { .inputCallDiscarded(.init(callId: $0)) },
            debugInformation: debugInformation,
        )
    }

    func sendCallLog(callId: Int?, path: String) async throws -> Ok {
        try await client.sendCallLog(
            callId: callId.map { .inputCallDiscarded(.init(callId: $0)) },
            logFile: .inputFileLocal(.init(path: path)),
        )
    }

    func sendCallRating(
        callId: Int?,
        comment: String?,
        problems: [TelegramCallRatingProblem]?,
        rating: Int?,
    ) async throws -> Ok {
        let tdlibProblems = problems?.map { problem -> CallProblem in
            switch problem {
            case .distortedSpeech: .callProblemDistortedSpeech
            case .distortedVideo: .callProblemDistortedVideo
            case .dropped: .callProblemDropped
            case .echo: .callProblemEcho
            case .interruptions: .callProblemInterruptions
            case .noise: .callProblemNoise
            case .pixelatedVideo: .callProblemPixelatedVideo
            case .silentLocal: .callProblemSilentLocal
            case .silentRemote: .callProblemSilentRemote
            }
        }
        return try await client.sendCallRating(
            callId: callId.map { .inputCallDiscarded(.init(callId: $0)) },
            comment: comment,
            problems: tdlibProblems,
            rating: rating,
        )
    }

    func createGroupCall(joinParameters: GroupCallJoinParameters?) async throws -> GroupCallInfo {
        try await client.createGroupCall(joinParameters: joinParameters)
    }

    func createVideoChat(
        chatId: Int64?,
        isRtmpStream: Bool?,
        startDate: Int?,
        title: String?,
    ) async throws -> GroupCallId {
        try await client.createVideoChat(
            chatId: chatId,
            isRtmpStream: isRtmpStream,
            startDate: startDate,
            title: title,
        )
    }

    func joinGroupCall(
        inputGroupCall: InputGroupCall?,
        joinParameters: GroupCallJoinParameters?,
    ) async throws -> GroupCallInfo {
        try await client.joinGroupCall(
            inputGroupCall: inputGroupCall,
            joinParameters: joinParameters,
        )
    }

    func joinVideoChat(
        groupCallId: Int?,
        inviteHash: String?,
        joinParameters: GroupCallJoinParameters?,
        participantId: MessageSender?,
    ) async throws -> Text {
        try await client.joinVideoChat(
            groupCallId: groupCallId,
            inviteHash: inviteHash,
            joinParameters: joinParameters,
            participantId: participantId,
        )
    }

    func getVideoChatAvailableParticipants(chatId: Int64?) async throws -> MessageSenders {
        try await client.getVideoChatAvailableParticipants(chatId: chatId)
    }

    func setVideoChatDefaultParticipant(
        chatId: Int64?,
        defaultParticipantId: MessageSender?,
    ) async throws -> Ok {
        try await client.setVideoChatDefaultParticipant(
            chatId: chatId,
            defaultParticipantId: defaultParticipantId,
        )
    }

    func getGroupCallStreams(groupCallId: Int?) async throws -> GroupCallStreams {
        try await client.getGroupCallStreams(groupCallId: groupCallId)
    }

    func getGroupCallStreamSegment(
        channelId: Int?,
        groupCallId: Int?,
        scale: Int?,
        timeOffset: Int64?,
        videoQuality: GroupCallVideoQuality?,
    ) async throws -> TdData {
        try await client.getGroupCallStreamSegment(
            channelId: channelId,
            groupCallId: groupCallId,
            scale: scale,
            timeOffset: timeOffset,
            videoQuality: videoQuality,
        )
    }

    func startScheduledVideoChat(groupCallId: Int?) async throws -> Ok {
        try await client.startScheduledVideoChat(groupCallId: groupCallId)
    }

    func toggleVideoChatEnabledStartNotification(
        enabledStartNotification: Bool?,
        groupCallId: Int?,
    ) async throws -> Ok {
        try await client.toggleVideoChatEnabledStartNotification(
            enabledStartNotification: enabledStartNotification,
            groupCallId: groupCallId,
        )
    }

    func getVideoChatInviteLink(canSelfUnmute: Bool?, groupCallId: Int?) async throws -> HttpUrl {
        try await client.getVideoChatInviteLink(canSelfUnmute: canSelfUnmute, groupCallId: groupCallId)
    }

    func inviteVideoChatParticipants(groupCallId: Int?, userIds: [Int64]?) async throws -> Ok {
        try await client.inviteVideoChatParticipants(groupCallId: groupCallId, userIds: userIds)
    }

    func revokeGroupCallInviteLink(groupCallId: Int?) async throws -> Ok {
        try await client.revokeGroupCallInviteLink(groupCallId: groupCallId)
    }

    func setVideoChatTitle(groupCallId: Int?, title: String?) async throws -> Ok {
        try await client.setVideoChatTitle(groupCallId: groupCallId, title: title)
    }

    func toggleVideoChatMuteNewParticipants(
        groupCallId: Int?,
        muteNewParticipants: Bool?,
    ) async throws -> Ok {
        try await client.toggleVideoChatMuteNewParticipants(
            groupCallId: groupCallId,
            muteNewParticipants: muteNewParticipants,
        )
    }

    func toggleGroupCallAreMessagesAllowed(areMessagesAllowed: Bool?, groupCallId: Int?) async throws -> Ok {
        try await client.toggleGroupCallAreMessagesAllowed(
            areMessagesAllowed: areMessagesAllowed,
            groupCallId: groupCallId,
        )
    }

    func startGroupCallRecording(
        groupCallId: Int?,
        recordVideo: Bool?,
        title: String?,
        usePortraitOrientation: Bool?,
    ) async throws -> Ok {
        try await client.startGroupCallRecording(
            groupCallId: groupCallId,
            recordVideo: recordVideo,
            title: title,
            usePortraitOrientation: usePortraitOrientation,
        )
    }

    func endGroupCallRecording(groupCallId: Int?) async throws -> Ok {
        try await client.endGroupCallRecording(groupCallId: groupCallId)
    }

    func getVideoChatRtmpUrl(chatId: Int64?) async throws -> RtmpUrl {
        try await client.getVideoChatRtmpUrl(chatId: chatId)
    }

    func replaceVideoChatRtmpUrl(chatId: Int64?) async throws -> RtmpUrl {
        try await client.replaceVideoChatRtmpUrl(chatId: chatId)
    }

    func startGroupCallScreenSharing(
        audioSourceId: Int?,
        groupCallId: Int?,
        payload: String?,
    ) async throws -> Text {
        try await client.startGroupCallScreenSharing(
            audioSourceId: audioSourceId,
            groupCallId: groupCallId,
            payload: payload,
        )
    }

    func endGroupCallScreenSharing(groupCallId: Int?) async throws -> Ok {
        try await client.endGroupCallScreenSharing(groupCallId: groupCallId)
    }

    func getGroupCall(groupCallId: Int?) async throws -> GroupCall {
        try await client.getGroupCall(groupCallId: groupCallId)
    }

    func getGroupCallParticipants(
        inputGroupCall: InputGroupCall?,
        limit: Int?,
    ) async throws -> GroupCallParticipants {
        try await client.getGroupCallParticipants(
            inputGroupCall: inputGroupCall,
            limit: limit,
        )
    }

    func inviteGroupCallParticipant(
        groupCallId: Int?,
        isVideo: Bool?,
        userId: Int64?,
    ) async throws -> InviteGroupCallParticipantResult {
        try await client.inviteGroupCallParticipant(
            groupCallId: groupCallId,
            isVideo: isVideo,
            userId: userId,
        )
    }

    func declineGroupCallInvitation(chatId: Int64?, messageId: Int64?) async throws -> Ok {
        try await client.declineGroupCallInvitation(chatId: chatId, messageId: messageId)
    }

    func toggleGroupCallParticipantIsMuted(
        groupCallId: Int?,
        isMuted: Bool?,
        participantId: MessageSender?,
    ) async throws -> Ok {
        try await client.toggleGroupCallParticipantIsMuted(
            groupCallId: groupCallId,
            isMuted: isMuted,
            participantId: participantId,
        )
    }

    func toggleGroupCallParticipantIsHandRaised(
        groupCallId: Int?,
        isHandRaised: Bool?,
        participantId: MessageSender?,
    ) async throws -> Ok {
        try await client.toggleGroupCallParticipantIsHandRaised(
            groupCallId: groupCallId,
            isHandRaised: isHandRaised,
            participantId: participantId,
        )
    }

    func setGroupCallParticipantVolumeLevel(
        groupCallId: Int?,
        participantId: MessageSender?,
        volumeLevel: Int?,
    ) async throws -> Ok {
        try await client.setGroupCallParticipantVolumeLevel(
            groupCallId: groupCallId,
            participantId: participantId,
            volumeLevel: volumeLevel,
        )
    }

    func banGroupCallParticipants(groupCallId: Int?, userIds: [TdInt64]?) async throws -> Ok {
        try await client.banGroupCallParticipants(groupCallId: groupCallId, userIds: userIds)
    }

    func loadGroupCallParticipants(groupCallId: Int?, limit: Int?) async throws -> Ok {
        try await client.loadGroupCallParticipants(groupCallId: groupCallId, limit: limit)
    }

    func sendGroupCallMessage(
        groupCallId: Int?,
        paidMessageStarCount: Int64?,
        text: FormattedText?,
    ) async throws -> Ok {
        try await client.sendGroupCallMessage(
            groupCallId: groupCallId,
            paidMessageStarCount: paidMessageStarCount,
            text: text,
        )
    }

    func encryptGroupCallData(
        data: Data?,
        dataChannel: GroupCallDataChannel?,
        groupCallId: Int?,
        unencryptedPrefixSize: Int?,
    ) async throws -> TdData {
        try await client.encryptGroupCallData(
            data: data,
            dataChannel: dataChannel,
            groupCallId: groupCallId,
            unencryptedPrefixSize: unencryptedPrefixSize,
        )
    }

    func encryptGroupCallData(
        data: Data,
        dataChannel: GroupCallDataChannel,
        groupCallId: Int,
        unencryptedPrefixSize: Int,
        completion: @escaping @Sendable (Data?) -> Void,
    ) {
        do {
            try client.encryptGroupCallData(
                data: data,
                dataChannel: dataChannel,
                groupCallId: groupCallId,
                unencryptedPrefixSize: unencryptedPrefixSize,
            ) { result in
                completion(try? result.get().data)
            }
        } catch {
            completion(nil)
        }
    }

    func decryptGroupCallData(
        data: Data?,
        dataChannel: GroupCallDataChannel?,
        groupCallId: Int?,
        participantId: MessageSender?,
    ) async throws -> TdData {
        try await client.decryptGroupCallData(
            data: data,
            dataChannel: dataChannel,
            groupCallId: groupCallId,
            participantId: participantId,
        )
    }

    func decryptGroupCallData(
        data: Data,
        dataChannel: GroupCallDataChannel?,
        groupCallId: Int,
        participantId: MessageSender,
        completion: @escaping @Sendable (Data?) -> Void,
    ) {
        do {
            try client.decryptGroupCallData(
                data: data,
                dataChannel: dataChannel,
                groupCallId: groupCallId,
                participantId: participantId,
            ) { result in
                completion(try? result.get().data)
            }
        } catch {
            completion(nil)
        }
    }

    func leaveGroupCall(groupCallId: Int?) async throws -> Ok {
        try await client.leaveGroupCall(groupCallId: groupCallId)
    }

    func endGroupCall(groupCallId: Int?) async throws -> Ok {
        try await client.endGroupCall(groupCallId: groupCallId)
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
