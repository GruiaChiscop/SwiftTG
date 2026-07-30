// ChatInfoDetailViews.swift

import SwiftUI
import TDLibKit

// MARK: - ChatInfoDestination

enum ChatInfoDestination: Hashable {
    case members(ChatInfoMemberFilter)
    case commonGroups(userId: Int64, count: Int)
}

// MARK: - ChatInfoMemberFilter

enum ChatInfoMemberFilter: String, Hashable {
    case members
    case administrators
    case restricted
    case banned

    // MARK: Internal

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

// MARK: - ChatInfoMember

private struct ChatInfoMember: Identifiable {
    let id: MessageSender
    let name: String
    let role: String?
    let presence: String?
    let photo: File?
    let minithumbnail: Minithumbnail?
    let placeholderId: Int64
}

// MARK: - ChatInfoMembersPage

private struct ChatInfoMembersPage {
    let members: [ChatInfoMember]
    let totalCount: Int
    let hasMore: Bool
    let nextOffset: Int
}

// MARK: - ChatInfoMembersView

struct ChatInfoMembersView: View {
    // MARK: Internal

    let chatId: Int64
    let isChannel: Bool
    let filter: ChatInfoMemberFilter
    let service: any TelegramService
    let onSelect: (MessageSender) -> Void

    var body: some View {
        List {
            if members.isEmpty, isLoading {
                HStack {
                    Spacer()
                    ProgressView("Loading \(displayTitle.lowercased())…")
                    Spacer()
                }
            } else if members.isEmpty, !query.isEmpty {
                ContentUnavailableView.search(text: query)
            } else if members.isEmpty {
                ContentUnavailableView(
                    "No \(displayTitle)",
                    systemImage: "person.2.slash",
                )
            }

            ForEach(members) { member in
                Button {
                    onSelect(member.id)
                } label: {
                    memberRow(member)
                }
                .buttonStyle(.plain)
            }

            if hasMore {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .onAppear { loadNextPage() }
            }
        }
        .navigationTitle(totalCount > 0 ? "\(displayTitle), \(totalCount)" : displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search \(displayTitle.lowercased())")
        .task(id: query) {
            if !query.isEmpty {
                try? await Task.sleep(for: .milliseconds(250))
            }
            guard !Task.isCancelled else { return }
            await reload()
        }
    }

    // MARK: Private

    @State private var hasMore = true
    @State private var isLoading = false
    @State private var loadGeneration: UInt64 = 0
    @State private var members = [ChatInfoMember]()
    @State private var nextOffset = 0
    @State private var query = ""
    @State private var totalCount = 0

    private var displayTitle: String {
        filter == .members && isChannel ? "Subscribers" : filter.title
    }

    private func memberRow(_ member: ChatInfoMember) -> some View {
        HStack(spacing: 12) {
            ProfileImageView(
                photo: member.photo,
                minithumbnail: member.minithumbnail,
                title: member.name,
                userId: member.placeholderId,
                fontSize: 18,
            )
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(member.name)
                let details = [member.role, member.presence].compactMap(\.self)
                if !details.isEmpty {
                    Text(details.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(.rect)
    }

    private func loadNextPage() {
        guard !isLoading, hasMore else { return }
        Task { await loadPage() }
    }

    private func reload() async {
        loadGeneration &+= 1
        let generation = loadGeneration
        isLoading = true
        let page = await loadMembersPage(query: query, offset: 0)
        guard !Task.isCancelled, generation == loadGeneration else { return }
        members = page?.members ?? []
        totalCount = page?.totalCount ?? 0
        hasMore = page?.hasMore ?? false
        nextOffset = page?.nextOffset ?? 0
        isLoading = false
    }

    private func loadPage() async {
        guard !isLoading else { return }
        let generation = loadGeneration
        let requestedQuery = query
        isLoading = true
        let page = await loadMembersPage(query: requestedQuery, offset: nextOffset)
        guard !Task.isCancelled, generation == loadGeneration, requestedQuery == query else { return }
        if let page {
            let knownIds = Set(members.map(\.id))
            members.append(contentsOf: page.members.filter { !knownIds.contains($0.id) })
            totalCount = page.totalCount
            hasMore = page.hasMore
            nextOffset = page.nextOffset
        } else {
            hasMore = false
        }
        isLoading = false
    }

    private func loadMembersPage(query: String, offset: Int) async -> ChatInfoMembersPage? {
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
                else {
                    return ChatInfoMembersPage(members: [], totalCount: 0, hasMore: false, nextOffset: 0)
                }
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
            else {
                return ChatInfoMembersPage(members: [], totalCount: 0, hasMore: false, nextOffset: 0)
            }
            result = searched
            supportsPagination = false
        case .chatTypePrivate, .chatTypeSecret:
            return nil
        }

        let resolved = await resolveMembers(result.members)
        return ChatInfoMembersPage(
            members: resolved,
            totalCount: result.totalCount,
            hasMore: supportsPagination && !result.members.isEmpty && offset + result.members.count < result.totalCount,
            nextOffset: offset + result.members.count,
        )
    }

    private func resolveMembers(_ members: [ChatMember]) async -> [ChatInfoMember] {
        let service = service
        let resolved = await withTaskGroup(of: (Int, ChatInfoMember?).self) { group in
            for (index, member) in members.enumerated() {
                group.addTask {
                    guard !Task.isCancelled else { return (index, nil) }
                    switch member.memberId {
                    case .messageSenderUser(let value):
                        guard let user = try? await service.getUser(userId: value.userId) else {
                            return (index, nil)
                        }
                        return (index, ChatInfoMember(
                            id: member.memberId,
                            name: telegramUserDisplayName(user),
                            role: chatInfoMemberRole(member.status, customTitle: member.tag),
                            presence: chatInfoUserPresence(user),
                            photo: user.profilePhoto?.small,
                            minithumbnail: user.profilePhoto?.minithumbnail,
                            placeholderId: user.id,
                        ))
                    case .messageSenderChat(let value):
                        guard let chat = try? await service.getChat(chatId: value.chatId) else {
                            return (index, nil)
                        }
                        return (index, ChatInfoMember(
                            id: member.memberId,
                            name: chat.title,
                            role: chatInfoMemberRole(member.status, customTitle: member.tag),
                            presence: nil,
                            photo: chat.photo?.small,
                            minithumbnail: chat.photo?.minithumbnail,
                            placeholderId: chat.id,
                        ))
                    }
                }
            }

            var collected = [(index: Int, member: ChatInfoMember)]()
            for await (index, member) in group {
                guard let member else { continue }
                collected.append((index, member))
            }
            return collected
        }
        return resolved.sorted { $0.index < $1.index }.map(\.member)
    }
}

// MARK: - ChatInfoCommonGroup

private struct ChatInfoCommonGroup: Identifiable {
    let chat: Chat

    var id: Int64 { chat.id }
}

// MARK: - ChatInfoCommonGroupsPage

private struct ChatInfoCommonGroupsPage {
    let groups: [ChatInfoCommonGroup]
    let hasMore: Bool
    let nextOffsetChatId: Int64
}

// MARK: - ChatInfoCommonGroupsView

struct ChatInfoCommonGroupsView: View {
    // MARK: Internal

    let userId: Int64
    let expectedCount: Int
    let service: any TelegramService
    let onSelect: (Chat) -> Void

    var body: some View {
        List {
            ForEach(groups) { group in
                Button {
                    onSelect(group.chat)
                } label: {
                    HStack(spacing: 12) {
                        ProfileImageView(
                            photo: group.chat.photo?.small,
                            minithumbnail: group.chat.photo?.minithumbnail,
                            title: group.chat.title,
                            userId: group.chat.id,
                            fontSize: 18,
                        )
                        .frame(width: 44, height: 44)
                        .accessibilityHidden(true)

                        Text(group.chat.title)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }

            if hasMore {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .onAppear { loadNextPage() }
            }
        }
        .overlay {
            if groups.isEmpty, isLoading {
                ProgressView("Loading groups in common…")
            } else if groups.isEmpty {
                ContentUnavailableView("No Groups in Common", systemImage: "person.2.slash")
            }
        }
        .navigationTitle(expectedCount > 0 ? "Groups in Common, \(expectedCount)" : "Groups in Common")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadGroups() }
    }

    // MARK: Private

    @State private var groups = [ChatInfoCommonGroup]()
    @State private var hasMore = true
    @State private var isLoading = true
    @State private var nextOffsetChatId: Int64 = 0

    private func loadGroups() async {
        let page = await loadPage(offsetChatId: 0)
        groups = page.groups
        hasMore = page.hasMore
        nextOffsetChatId = page.nextOffsetChatId
        isLoading = false
    }

    private func loadNextPage() {
        guard !isLoading, hasMore else { return }
        isLoading = true
        Task {
            let page = await loadPage(offsetChatId: nextOffsetChatId)
            let knownIds = Set(groups.map(\.id))
            groups.append(contentsOf: page.groups.filter { !knownIds.contains($0.id) })
            hasMore = page.hasMore
            nextOffsetChatId = page.nextOffsetChatId
            isLoading = false
        }
    }

    private func loadPage(offsetChatId: Int64) async -> ChatInfoCommonGroupsPage {
        guard !Task.isCancelled,
              let page = try? await service.getGroupsInCommon(
                  limit: 50,
                  offsetChatId: offsetChatId,
                  userId: userId,
              )
        else {
            return ChatInfoCommonGroupsPage(groups: [], hasMore: false, nextOffsetChatId: offsetChatId)
        }

        let service = service
        let resolved = await withTaskGroup(of: (Int, ChatInfoCommonGroup?).self) { group in
            for (index, chatId) in page.chatIds.enumerated() {
                group.addTask {
                    guard !Task.isCancelled, let chat = try? await service.getChat(chatId: chatId) else {
                        return (index, nil)
                    }
                    return (index, ChatInfoCommonGroup(chat: chat))
                }
            }

            var collected = [(index: Int, group: ChatInfoCommonGroup)]()
            for await (index, commonGroup) in group {
                guard let commonGroup else { continue }
                collected.append((index, commonGroup))
            }
            return collected
        }
        return ChatInfoCommonGroupsPage(
            groups: resolved.sorted { $0.index < $1.index }.map(\.group),
            hasMore: page.chatIds.count == 50,
            nextOffsetChatId: page.chatIds.last ?? offsetChatId,
        )
    }
}

private func chatInfoMemberRole(_ status: ChatMemberStatus, customTitle: String) -> String? {
    if !customTitle.isEmpty {
        return customTitle
    }
    switch status {
    case .chatMemberStatusCreator:
        return "Owner"
    case .chatMemberStatusAdministrator:
        return "Administrator"
    case .chatMemberStatusRestricted:
        return "Restricted"
    case .chatMemberStatusBanned:
        return "Banned"
    case .chatMemberStatusLeft, .chatMemberStatusMember:
        return nil
    }
}

private func chatInfoUserPresence(_ user: User) -> String {
    switch user.type {
    case .userTypeBot:
        "Bot"
    case .userTypeDeleted:
        "Deleted account"
    case .userTypeRegular, .userTypeUnknown:
        telegramUserPresenceDescription(user.status)
    }
}
