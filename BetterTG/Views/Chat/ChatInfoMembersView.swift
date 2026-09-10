// ChatInfoMembersView.swift

import SwiftUI
import TDLibKit

struct ChatInfoMembersView: View {
    // MARK: Internal

    let chatId: Int64
    let isChannel: Bool
    let filter: TelegramChatInfoMemberFilter
    let service: any TelegramService

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
                    openMember(member.id)
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
            await reload(query: query)
        }
        // Declared here (not on the ancestor ChatInfoView) so it stacks directly on top of this
        // screen - a `.navigationDestination` registered on an ancestor view inserts its pushed
        // content at the ancestor's position, not on top of whatever's currently the deepest
        // active push, which sent the back button to the wrong screen.
        .navigationDestination(item: $pushedChat) { customChat in
            ChatView(customChat: customChat, backButtonTitleOverride: displayTitle)
        }
        .alert("Can't Open Chat", isPresented: errorIsPresented) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Private

    @State private var errorMessage: String?
    @State private var hasMore = true
    @State private var isLoading = false
    @State private var loadGeneration: UInt64 = 0
    @State private var members = [TelegramChatInfoMember]()
    @State private var nextOffset = 0
    @State private var pushedChat: CustomChat?
    @State private var query = ""
    @State private var totalCount = 0

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    errorMessage = nil
                }
            },
        )
    }

    private var displayTitle: String {
        filter == .members && isChannel ? "Subscribers" : filter.title
    }

    private func memberRow(_ member: TelegramChatInfoMember) -> some View {
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

    private func openMember(_ sender: MessageSender) {
        Task {
            let customChat: CustomChat? =
                switch sender {
                case .messageSenderUser(let value):
                    await RootVM.shared.getPrivateCustomChat(userId: value.userId)
                case .messageSenderChat(let value):
                    await RootVM.shared.getCustomChat(from: value.chatId)
                }
            guard let customChat else {
                errorMessage = "This chat is private or unavailable."
                return
            }
            pushedChat = customChat
        }
    }

    private func loadNextPage() {
        guard !isLoading, hasMore else { return }
        Task { await loadPage() }
    }

    private func reload(query requestedQuery: String) async {
        loadGeneration &+= 1
        let generation = loadGeneration
        isLoading = true
        let page = await TelegramChatInfoLoader(service: service).loadMembers(
            chatId: chatId,
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

    private func loadPage() async {
        guard !isLoading else { return }
        let generation = loadGeneration
        let requestedQuery = query
        isLoading = true
        let page = await TelegramChatInfoLoader(service: service).loadMembers(
            chatId: chatId,
            filter: filter,
            query: requestedQuery,
            offset: nextOffset,
        )
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
}
