// TelegramChatInfoMemberFilter.swift

import TDLibKit

enum TelegramChatInfoMemberFilter: String, Hashable, Identifiable {
    case members
    case administrators
    case restricted
    case banned

    // MARK: Internal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .members: "Members"
        case .administrators: "Administrators"
        case .restricted: "Restricted"
        case .banned: "Banned"
        }
    }

    var chatFilter: ChatMembersFilter {
        switch self {
        case .members: .chatMembersFilterMembers
        case .administrators: .chatMembersFilterAdministrators
        case .restricted: .chatMembersFilterRestricted
        case .banned: .chatMembersFilterBanned
        }
    }

    func supergroupFilter(query: String) -> SupergroupMembersFilter {
        switch self {
        case .members:
            query.isEmpty
                ? .supergroupMembersFilterRecent
                : .supergroupMembersFilterSearch(.init(query: query))
        case .administrators:
            .supergroupMembersFilterAdministrators
        case .restricted:
            .supergroupMembersFilterRestricted(.init(query: query))
        case .banned:
            .supergroupMembersFilterBanned(.init(query: query))
        }
    }
}
