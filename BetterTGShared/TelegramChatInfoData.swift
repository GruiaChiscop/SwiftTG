// TelegramChatInfoData.swift

import TDLibKit

struct TelegramChatInfoData: Equatable {
    let chatId: Int64
    let title: String
    let kind: String
    let photoFileId: Int?
    /// Whether this is the chat with yourself - `title`/`photoFileId` above already reflect this
    /// (`"Saved Messages"`, no photo), kept as an explicit flag so views can show a dedicated
    /// bookmark icon rather than inferring it from a merely-absent photo, which also legitimately
    /// happens for ordinary contacts with no photo set.
    let isSavedMessages: Bool
    var about: FormattedText?
    var usernames = [String]()
    var phoneNumber: String?
    var birthdate: String?
    var memberCount: Int?
    var administratorCount: Int?
    var restrictedCount: Int?
    var bannedCount: Int?
    var commonGroupCount: Int?
    var commonGroupsUserId: Int64?
    var isBlocked = false
    /// Current message auto-delete / self-destruct time for this chat, in seconds. 0 = off.
    var messageAutoDeleteTime = 0
    /// Trust/identity badges shown in the header. `isScam`/`isFake` come from the peer's
    /// `verificationStatus`; `isPremium` is user-only.
    var isVerified = false
    var isScam = false
    var isFake = false
    var isPremium = false
    var defaultMuteFor = 0
    var defaultShowPreview = true
    var defaultMuteStories = false
    var usesUnofficialApp = false
    var privacyPolicyURL: String?
    var usesPrivacyCommand = false
    var members = [TelegramChatInfoMember]()
    var memberTotalCount = 0
    var canBrowseMembers = false
    var canManageMembers = false
    var canRestrictMembers = false
    /// `change_info` admin right (or creator) - TDLib requires it to change the chat's
    /// message-auto-delete time in a group/channel.
    var canChangeInfo = false
    var canLeave = false
    var canDeleteCommunity = false
    /// Read-only group/channel details surfaced in `ChatInfoView`. `linkedChatId` is 0 when none;
    /// `slowModeDelay` is in seconds (0 = off).
    var slowModeDelay = 0
    var linkedChatId: Int64 = 0
    var linkedChatTitle: String?
    var hasHiddenMembers = false
    var signMessages = false
    var hasProtectedContent = false
    var reactionsSummary: String?
    var isBot = false
    var blockableUserId: Int64?
    var callUserId: Int64?
    /// The other person's user id for a 1:1 chat with a regular (non-bot, non-deleted) user that
    /// isn't yourself - drives "Start Secret Chat" and "Add to Contacts".
    var privateChatUserId: Int64?
    var isContact = false
    var contactFirstName = ""
    var contactLastName = ""
    /// The user's public "personal channel" shown on their profile (`personalChatId` is 0 when
    /// none).
    var personalChatId: Int64 = 0
    var personalChatTitle: String?
    var canStartAudioCall = false
    var canStartVideoCall = false
}
