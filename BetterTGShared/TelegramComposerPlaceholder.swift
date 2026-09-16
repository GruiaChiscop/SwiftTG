// TelegramComposerPlaceholder.swift

import TDLibKit

/// True when `status` posts anonymously in its chat (an anonymous admin, or creator with
/// anonymity turned on) - only ever applicable to supergroups/channels, per
/// `ChatMemberStatusCreator.isAnonymous`'s own doc comment.
func telegramIsAnonymousAdmin(_ status: ChatMemberStatus?) -> Bool {
    switch status {
    case .chatMemberStatusCreator(let value): value.isAnonymous
    case .chatMemberStatusAdministrator(let value): value.rights.isAnonymous
    default: false
    }
}

/// The message composer's placeholder override - "Broadcast"/"Silent Broadcast" for channels,
/// "Send Anonymously" for an anonymous admin/creator, or `nil` to use the caller's own default.
/// Mirrors Unigram's `ChatView.GetPlaceholder`.
func telegramComposerPlaceholder(
    isChannel: Bool,
    defaultDisableNotification: Bool,
    status: ChatMemberStatus?,
) -> String? {
    if isChannel {
        return defaultDisableNotification ? "Silent Broadcast" : "Broadcast"
    }
    return telegramIsAnonymousAdmin(status) ? "Send Anonymously" : nil
}
