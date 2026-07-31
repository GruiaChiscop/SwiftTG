// MacChatMembers.swift

import SwiftUI
import TDLibKit

// MARK: - MacChatMemberListFilter

enum MacChatMemberListFilter: String, Identifiable {
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

// MARK: - MacChatMembersPage

struct MacChatMembersPage {
    let members: [MacChatInfoMember]
    let totalCount: Int
    let hasMore: Bool
    let nextOffset: Int
}

// MARK: - MacChatMembersView

struct MacChatMembersView: View {
    // MARK: Internal

    @Bindable var model: MacSessionModel

    let chat: ChatListItemState
    let filter: MacChatMemberListFilter
    let onSelect: (MessageSender) -> Void

    var body: some View {
        NavigationStack {
            List {
                TextField("Search \(displayTitle.lowercased())", text: $query)
                    .textFieldStyle(.roundedBorder)

                if members.isEmpty, isLoading {
                    ProgressView("Loading \(displayTitle.lowercased())…")
                        .frame(maxWidth: .infinity)
                        .padding()
                } else if members.isEmpty, !query.isEmpty {
                    ContentUnavailableView.search(text: query)
                }

                ForEach(members) { member in
                    Button {
                        dismiss()
                        onSelect(member.id)
                    } label: {
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
                    .buttonStyle(.plain)
                }

                if hasMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .onAppear { loadNextPage() }
                }
            }
            .listStyle(.inset)
            .navigationTitle(totalCount > 0 ? "\(displayTitle), \(totalCount)" : displayTitle)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 480, idealWidth: 560, minHeight: 520, idealHeight: 680)
        .task(id: query) {
            await reload(query: query)
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var members = [MacChatInfoMember]()
    @State private var totalCount = 0
    @State private var hasMore = true
    @State private var isLoading = false
    @State private var loadGeneration: UInt64 = 0
    @State private var nextOffset = 0

    private var displayTitle: String {
        filter == .members && chat.kind == .channel ? "Subscribers" : filter.title
    }

    private func loadNextPage() {
        guard !isLoading, hasMore else { return }
        Task { await loadPage(reset: false) }
    }

    private func reload(query requestedQuery: String) async {
        loadGeneration &+= 1
        let generation = loadGeneration
        isLoading = true
        let page = await model.loadChatInfoMembers(
            for: chat,
            filter: filter,
            query: requestedQuery,
            offset: 0,
        )
        guard !Task.isCancelled, generation == loadGeneration, requestedQuery == query else { return }
        members = page?.members ?? []
        totalCount = page?.totalCount ?? 0
        hasMore = page?.hasMore ?? false
        nextOffset = page?.nextOffset ?? 0
        isLoading = false
    }

    private func loadPage(reset: Bool) async {
        guard !isLoading else { return }
        let generation = loadGeneration
        let requestedQuery = query
        isLoading = true
        let offset = reset ? 0 : nextOffset
        let page = await model.loadChatInfoMembers(
            for: chat,
            filter: filter,
            query: requestedQuery,
            offset: offset,
        )
        guard !Task.isCancelled, generation == loadGeneration, requestedQuery == query else { return }
        if reset {
            members = page?.members ?? []
        } else if let page {
            let knownIds = Set(members.map(\.id))
            members.append(contentsOf: page.members.filter { !knownIds.contains($0.id) })
        }
        totalCount = page?.totalCount ?? 0
        hasMore = page?.hasMore ?? false
        nextOffset = page?.nextOffset ?? nextOffset
        isLoading = false
    }
}

extension MacSessionModel {
    func loadChatInfoMembers(
        for state: ChatListItemState,
        filter: MacChatMemberListFilter,
        query: String,
        offset: Int,
    ) async -> MacChatMembersPage? {
        guard let chat = try? await service.getChat(chatId: state.chatId) else { return nil }
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
                else { return MacChatMembersPage(members: [], totalCount: 0, hasMore: false, nextOffset: 0) }
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
            else { return MacChatMembersPage(members: [], totalCount: 0, hasMore: false, nextOffset: 0) }
            result = searched
            supportsPagination = false
        case .chatTypePrivate, .chatTypeSecret:
            return nil
        }

        let resolved = await resolveChatInfoMembers(result.members)
        return MacChatMembersPage(
            members: resolved,
            totalCount: result.totalCount,
            hasMore: supportsPagination && !result.members.isEmpty && offset + result.members.count < result.totalCount,
            nextOffset: offset + result.members.count,
        )
    }
}
