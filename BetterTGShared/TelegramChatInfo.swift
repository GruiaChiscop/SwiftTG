// TelegramChatInfo.swift

import Foundation
@preconcurrency import TDLibKit

// MARK: - TelegramChatInfoMember

struct TelegramChatInfoMember: Identifiable, Equatable {
    let id: MessageSender
    let name: String
    let role: String?
    let presence: String?
    let photo: File?
    let minithumbnail: Minithumbnail?
    let placeholderId: Int64
}

// MARK: - TelegramChatInfoData

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
    var defaultMuteFor = 0
    var usesUnofficialApp = false
    var privacyPolicyURL: String?
    var usesPrivacyCommand = false
    var members = [TelegramChatInfoMember]()
    var memberTotalCount = 0
    var canBrowseMembers = false
    var canManageMembers = false
    var canRestrictMembers = false
    var canLeave = false
    var canDeleteCommunity = false
    var isBot = false
    var blockableUserId: Int64?
    var callUserId: Int64?
    var canStartAudioCall = false
    var canStartVideoCall = false
}

// MARK: - TelegramChatInfoMemberFilter

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

// MARK: - TelegramChatInfoMembersPage

struct TelegramChatInfoMembersPage {
    let members: [TelegramChatInfoMember]
    let totalCount: Int
    let hasMore: Bool
    let nextOffset: Int
}

// MARK: - TelegramChatInfoCommonGroupsPage

struct TelegramChatInfoCommonGroupsPage {
    let groups: [Chat]
    let hasMore: Bool
    let nextOffsetChatId: Int64
}

// MARK: - TelegramChatInfoLoader

struct TelegramChatInfoLoader {
    // MARK: Internal

    let service: any TelegramService

    func load(chatId: Int64) async throws -> TelegramChatInfoData {
        let chat = try await service.getChat(chatId: chatId)
        let currentUserId = await TelegramCurrentUserCache.shared.userId(service: service)
        let isSavedMessages: Bool =
            if case .chatTypePrivate(let value) = chat.type {
                telegramIsSavedMessages(entityUserId: value.userId, currentUserId: currentUserId)
            } else {
                false
            }
        var info = TelegramChatInfoData(
            chatId: chat.id,
            title: telegramDisplayTitle(title: chat.title, isSavedMessages: isSavedMessages),
            kind: ChatListItemKind(chat.type).accessibilityTitle ?? "Private chat",
            photoFileId: isSavedMessages ? nil : chat.photo?.small.id,
            isSavedMessages: isSavedMessages,
        )
        let scope = telegramNotificationScope(for: chat.type)
        info.defaultMuteFor = await (try? service.getScopeNotificationSettings(scope: scope))?.muteFor ?? 0

        switch chat.type {
        case .chatTypePrivate(let value):
            await populateUserInfo(&info, userId: value.userId)
        case .chatTypeSecret(let value):
            await populateUserInfo(&info, userId: value.userId)
        case .chatTypeBasicGroup(let value):
            await populateBasicGroupInfo(&info, groupId: value.basicGroupId)
        case .chatTypeSupergroup(let value):
            await populateSupergroupInfo(&info, groupId: value.supergroupId)
        }
        return info
    }

    func loadMembers(
        chatId: Int64,
        filter: TelegramChatInfoMemberFilter,
        query: String,
        offset: Int,
    ) async -> TelegramChatInfoMembersPage? {
        guard let chat = try? await service.getChat(chatId: chatId) else { return nil }
        let result: ChatMembers
        let supportsPagination: Bool

        switch chat.type {
        case .chatTypeSupergroup(let value):
            if filter == .administrators, !query.isEmpty {
                guard offset == 0,
                      let searched = try? await service.searchChatMembers(
                          chatId: chat.id,
                          filter: filter.chatFilter,
                          limit: 50,
                          query: query,
                      )
                else { return emptyMembersPage }
                result = searched
                supportsPagination = false
            } else {
                guard let page = try? await service.getSupergroupMembers(
                    filter: filter.supergroupFilter(query: query),
                    limit: 50,
                    offset: offset,
                    supergroupId: value.supergroupId,
                ) else { return nil }
                result = page
                supportsPagination = true
            }
        case .chatTypeBasicGroup:
            guard offset == 0,
                  let searched = try? await service.searchChatMembers(
                      chatId: chat.id,
                      filter: filter.chatFilter,
                      limit: 200,
                      query: query,
                  )
            else { return emptyMembersPage }
            result = searched
            supportsPagination = false
        case .chatTypePrivate, .chatTypeSecret:
            return nil
        }

        let members = await resolveMembers(result.members)
        return TelegramChatInfoMembersPage(
            members: members,
            totalCount: result.totalCount,
            hasMore: supportsPagination && !result.members.isEmpty && offset + result.members.count < result.totalCount,
            nextOffset: offset + result.members.count,
        )
    }

    func loadCommonGroups(userId: Int64, offsetChatId: Int64) async -> TelegramChatInfoCommonGroupsPage {
        guard !Task.isCancelled,
              let page = try? await service.getGroupsInCommon(
                  limit: 50,
                  offsetChatId: offsetChatId,
                  userId: userId,
              )
        else {
            return TelegramChatInfoCommonGroupsPage(
                groups: [],
                hasMore: false,
                nextOffsetChatId: offsetChatId,
            )
        }

        let service = service
        let resolved = await withTaskGroup(of: (Int, Chat?).self) { group in
            for (index, chatId) in page.chatIds.enumerated() {
                group.addTask {
                    guard !Task.isCancelled else { return (index, nil) }
                    return await (index, try? service.getChat(chatId: chatId))
                }
            }
            var collected = [(index: Int, chat: Chat)]()
            for await (index, chat) in group {
                guard let chat else { continue }
                collected.append((index, chat))
            }
            return collected.sorted { $0.index < $1.index }.map(\.chat)
        }
        return TelegramChatInfoCommonGroupsPage(
            groups: resolved,
            hasMore: page.chatIds.count == 50,
            nextOffsetChatId: page.chatIds.last ?? offsetChatId,
        )
    }

    func resolveMembers(_ members: [ChatMember]) async -> [TelegramChatInfoMember] {
        let service = service
        let resolved = await withTaskGroup(of: (Int, TelegramChatInfoMember?).self) { group in
            for (index, member) in members.enumerated() {
                group.addTask {
                    guard !Task.isCancelled else { return (index, nil) }
                    switch member.memberId {
                    case .messageSenderUser(let value):
                        guard let user = try? await service.getUser(userId: value.userId) else { return (index, nil) }
                        return (index, TelegramChatInfoMember(
                            id: member.memberId,
                            name: telegramUserDisplayName(user),
                            role: telegramChatMemberRole(member.status, customTitle: member.tag),
                            presence: telegramChatInfoUserPresence(user),
                            photo: user.profilePhoto?.small,
                            minithumbnail: user.profilePhoto?.minithumbnail,
                            placeholderId: user.id,
                        ))
                    case .messageSenderChat(let value):
                        guard let chat = try? await service.getChat(chatId: value.chatId) else { return (index, nil) }
                        return (index, TelegramChatInfoMember(
                            id: member.memberId,
                            name: chat.title,
                            role: telegramChatMemberRole(member.status, customTitle: member.tag),
                            presence: nil,
                            photo: chat.photo?.small,
                            minithumbnail: chat.photo?.minithumbnail,
                            placeholderId: chat.id,
                        ))
                    }
                }
            }
            var collected = [(index: Int, member: TelegramChatInfoMember)]()
            for await (index, member) in group {
                guard let member else { continue }
                collected.append((index, member))
            }
            return collected
        }
        return resolved.sorted { $0.index < $1.index }.map(\.member)
    }

    // MARK: Private

    private var emptyMembersPage: TelegramChatInfoMembersPage {
        TelegramChatInfoMembersPage(members: [], totalCount: 0, hasMore: false, nextOffset: 0)
    }

    private func populateUserInfo(_ info: inout TelegramChatInfoData, userId: Int64) async {
        guard let user = try? await service.getUser(userId: userId) else { return }
        info.usernames = user.usernames?.activeUsernames ?? []
        info.phoneNumber = user.phoneNumber.isEmpty ? nil : "+\(user.phoneNumber)"
        let currentUserId = await (try? service.getMe())?.id
        let isRegularUser =
            if case .userTypeRegular = user.type {
                true
            } else {
                false
            }
        let isCallEligible = isRegularUser && !user.isSupport && userId != currentUserId
        info.callUserId = isCallEligible ? userId : nil
        switch user.type {
        case .userTypeBot:
            info.isBot = true
            info.blockableUserId = userId == currentUserId ? nil : userId
        case .userTypeRegular:
            info.blockableUserId = userId == currentUserId ? nil : userId
        case .userTypeDeleted, .userTypeUnknown:
            break
        }

        guard let full = try? await service.getUserFullInfo(userId: userId) else { return }
        if let shortDescription = full.botInfo?.shortDescription.telegramNilIfEmpty {
            info.about = FormattedText(entities: [], text: shortDescription)
        } else if let bio = full.bio, !bio.text.isEmpty {
            info.about = bio
        }
        info.birthdate = full.birthdate.map(telegramBirthdateDescription)
        info.commonGroupCount = full.groupInCommonCount
        info.commonGroupsUserId = full.groupInCommonCount > 0 ? userId : nil
        info.isBlocked = full.blockList == .blockListMain
        info.usesUnofficialApp = full.usesUnofficialApp
        info.canStartAudioCall = isCallEligible && full.canBeCalled
        info.canStartVideoCall = info.canStartAudioCall && full.supportsVideoCalls
        if let botInfo = full.botInfo {
            if let privacyPolicyURL = botInfo.privacyPolicyUrl.telegramNilIfEmpty {
                info.privacyPolicyURL = privacyPolicyURL
            } else if botInfo.commands.contains(where: { $0.command == "privacy" }) {
                info.usesPrivacyCommand = true
            } else {
                info.privacyPolicyURL = "https://telegram.org/privacy-tpa"
            }
        }
    }

    private func populateBasicGroupInfo(_ info: inout TelegramChatInfoData, groupId: Int64) async {
        guard let group = try? await service.getBasicGroup(basicGroupId: groupId) else { return }
        info.memberCount = group.memberCount
        info.canLeave = telegramCanLeaveChat(group.status)
        info.canDeleteCommunity = telegramIsChatCreator(group.status)
        info.canManageMembers = telegramCanManageMembers(group.status)
        info.canRestrictMembers = telegramCanRestrictMembers(group.status)
        info.canBrowseMembers = true

        guard let full = try? await service.getBasicGroupFullInfo(basicGroupId: groupId) else { return }
        info.about = full.description.telegramNilIfEmpty.map { FormattedText(entities: [], text: $0) }
        info.memberCount = max(group.memberCount, full.members.count)
        info.memberTotalCount = full.members.count
        if info.canManageMembers {
            info.administratorCount = full.members.filter { telegramIsChatAdministrator($0.status) }.count
        }
        if info.canRestrictMembers {
            info.restrictedCount = full.members
                .filter { member in
                    if case .chatMemberStatusRestricted = member.status {
                        true
                    } else {
                        false
                    }
                }
                .count
            info.bannedCount = full.members
                .filter { member in
                    if case .chatMemberStatusBanned = member.status {
                        true
                    } else {
                        false
                    }
                }
                .count
        }
        if full.members.count <= 5 {
            info.members = await resolveMembers(full.members)
        }
    }

    private func populateSupergroupInfo(_ info: inout TelegramChatInfoData, groupId: Int64) async {
        guard let group = try? await service.getSupergroup(supergroupId: groupId) else { return }
        info.usernames = group.usernames?.activeUsernames ?? []
        info.memberCount = group.memberCount > 0 ? group.memberCount : nil
        info.canLeave = telegramCanLeaveChat(group.status)
        info.canDeleteCommunity = telegramIsChatCreator(group.status)
        info.canManageMembers = telegramCanManageMembers(group.status)
        info.canRestrictMembers = telegramCanRestrictMembers(group.status)

        guard let full = try? await service.getSupergroupFullInfo(supergroupId: groupId) else { return }
        info.about = full.description.telegramNilIfEmpty.map { FormattedText(entities: [], text: $0) }
        info.memberCount = max(group.memberCount, full.memberCount)
        info.memberTotalCount = full.memberCount
        info.canBrowseMembers = full.canGetMembers
        if info.canManageMembers {
            info.administratorCount = full.administratorCount
        }
        if info.canRestrictMembers {
            info.restrictedCount = full.restrictedCount
            info.bannedCount = full.bannedCount
        }
        if full.canGetMembers,
           full.memberCount <= 5,
           let result = try? await service.getSupergroupMembers(
               filter: .supergroupMembersFilterRecent,
               limit: 5,
               offset: 0,
               supergroupId: groupId,
           )
        {
            info.memberTotalCount = result.totalCount
            info.members = await resolveMembers(result.members)
        }
    }
}

// MARK: - Shared chat-info semantics

func telegramNotificationScope(for type: ChatType) -> NotificationSettingsScope {
    switch type {
    case .chatTypePrivate, .chatTypeSecret:
        .notificationSettingsScopePrivateChats
    case .chatTypeBasicGroup:
        .notificationSettingsScopeGroupChats
    case .chatTypeSupergroup(let value):
        value.isChannel ? .notificationSettingsScopeChannelChats : .notificationSettingsScopeGroupChats
    }
}

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

func telegramBirthdateDescription(_ birthdate: Birthdate) -> String {
    let calendar = Calendar.autoupdatingCurrent
    let now = Date()
    var components = DateComponents()
    components.calendar = calendar
    components.day = birthdate.day
    components.month = birthdate.month
    components.year = birthdate.year == 0 ? 2000 : birthdate.year
    guard let date = components.date else { return "\(birthdate.day)/\(birthdate.month)" }

    var description = date.formatted(
        Date.FormatStyle()
            .month(.wide)
            .day()
            .year(birthdate.year == 0 ? .omitted : .defaultDigits),
    )
    if birthdate.year > 0 {
        let age = calendar.dateComponents([.year], from: date, to: now).year ?? 0
        if age >= 0 {
            description += ", \(age) years old"
        }
    }
    let today = calendar.dateComponents([.day, .month], from: now)
    if today.day == birthdate.day, today.month == birthdate.month {
        description += ", birthday today"
    }
    return description
}

private func telegramChatInfoUserPresence(_ user: User) -> String {
    switch user.type {
    case .userTypeBot: "Bot"
    case .userTypeDeleted: "Deleted account"
    case .userTypeRegular, .userTypeUnknown: telegramUserPresenceDescription(user.status)
    }
}

private extension String {
    var telegramNilIfEmpty: String? { isEmpty ? nil : self }
}
