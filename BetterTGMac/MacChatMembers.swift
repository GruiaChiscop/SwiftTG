// MacChatMembers.swift

import SwiftUI
import TDLibKit

// MARK: - MacChatMembersView

struct MacChatMembersView: View {
    // MARK: Internal

    @Bindable var model: MacSessionModel

    let chat: ChatListItemState
    let filter: TelegramChatInfoMemberFilter
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
    @State private var members = [TelegramChatInfoMember]()
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
        let page = await TelegramChatInfoLoader(service: model.service).loadMembers(
            chatId: chat.chatId,
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
        let page = await TelegramChatInfoLoader(service: model.service).loadMembers(
            chatId: chat.chatId,
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
