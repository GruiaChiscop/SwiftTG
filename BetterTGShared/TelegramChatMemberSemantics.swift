// TelegramChatMemberSemantics.swift

import TDLibKit

// Predicates over `ChatMemberStatus`, shared by `TelegramChatInfoLoader` and the info views.

func telegramCanLeaveChat(_ status: ChatMemberStatus) -> Bool {
    switch status {
    case .chatMemberStatusMember:
        true
    case .chatMemberStatusRestricted(let value):
        value.isMember
    case .chatMemberStatusAdministrator, .chatMemberStatusBanned, .chatMemberStatusCreator, .chatMemberStatusLeft:
        false
    }
}

func telegramCanManageMembers(_ status: ChatMemberStatus) -> Bool {
    switch status {
    case .chatMemberStatusAdministrator, .chatMemberStatusCreator:
        true
    case .chatMemberStatusBanned, .chatMemberStatusLeft, .chatMemberStatusMember, .chatMemberStatusRestricted:
        false
    }
}

func telegramCanRestrictMembers(_ status: ChatMemberStatus) -> Bool {
    switch status {
    case .chatMemberStatusCreator:
        true
    case .chatMemberStatusAdministrator(let value):
        value.rights.canRestrictMembers
    case .chatMemberStatusBanned, .chatMemberStatusLeft, .chatMemberStatusMember, .chatMemberStatusRestricted:
        false
    }
}

func telegramCanChangeInfo(_ status: ChatMemberStatus) -> Bool {
    switch status {
    case .chatMemberStatusCreator:
        true
    case .chatMemberStatusAdministrator(let value):
        value.rights.canChangeInfo
    case .chatMemberStatusBanned, .chatMemberStatusLeft, .chatMemberStatusMember, .chatMemberStatusRestricted:
        false
    }
}

func telegramIsChatAdministrator(_ status: ChatMemberStatus) -> Bool {
    switch status {
    case .chatMemberStatusAdministrator, .chatMemberStatusCreator:
        true
    case .chatMemberStatusBanned, .chatMemberStatusLeft, .chatMemberStatusMember, .chatMemberStatusRestricted:
        false
    }
}

func telegramIsChatCreator(_ status: ChatMemberStatus) -> Bool {
    if case .chatMemberStatusCreator = status {
        return true
    }
    return false
}

func telegramChatMemberRole(_ status: ChatMemberStatus, customTitle: String = "") -> String? {
    if !customTitle.isEmpty {
        return customTitle
    }
    return switch status {
    case .chatMemberStatusCreator: "Owner"
    case .chatMemberStatusAdministrator: "Administrator"
    case .chatMemberStatusRestricted: "Restricted"
    case .chatMemberStatusBanned: "Banned"
    case .chatMemberStatusLeft, .chatMemberStatusMember: nil
    }
}
