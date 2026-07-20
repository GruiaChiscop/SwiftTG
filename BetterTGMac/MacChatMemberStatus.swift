// MacChatMemberStatus.swift

import TDLibKit

func macCanLeaveChat(_ status: ChatMemberStatus) -> Bool {
    switch status {
    case .chatMemberStatusMember:
        true
    case .chatMemberStatusRestricted(let value):
        value.isMember
    case .chatMemberStatusAdministrator, .chatMemberStatusBanned, .chatMemberStatusCreator, .chatMemberStatusLeft:
        false
    }
}

func macCanManageMembers(_ status: ChatMemberStatus) -> Bool {
    switch status {
    case .chatMemberStatusAdministrator, .chatMemberStatusCreator:
        true
    case .chatMemberStatusBanned, .chatMemberStatusLeft, .chatMemberStatusMember,
         .chatMemberStatusRestricted:
        false
    }
}

func macIsAdministrator(_ status: ChatMemberStatus) -> Bool {
    switch status {
    case .chatMemberStatusAdministrator, .chatMemberStatusCreator:
        true
    case .chatMemberStatusBanned, .chatMemberStatusLeft, .chatMemberStatusMember,
         .chatMemberStatusRestricted:
        false
    }
}

func macCanRestrictMembers(_ status: ChatMemberStatus) -> Bool {
    switch status {
    case .chatMemberStatusCreator:
        true
    case .chatMemberStatusAdministrator(let value):
        value.rights.canRestrictMembers
    case .chatMemberStatusBanned, .chatMemberStatusLeft, .chatMemberStatusMember,
         .chatMemberStatusRestricted:
        false
    }
}

func macIsCreator(_ status: ChatMemberStatus) -> Bool {
    if case .chatMemberStatusCreator = status {
        return true
    }
    return false
}
