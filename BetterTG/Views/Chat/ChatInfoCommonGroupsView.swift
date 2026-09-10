// ChatInfoCommonGroupsView.swift

import SwiftUI
import TDLibKit

struct ChatInfoCommonGroupsView: View {
    // MARK: Internal

    let userId: Int64
    let expectedCount: Int
    let service: any TelegramService

    var body: some View {
        List {
            ForEach(groups, id: \.id) { group in
                Button {
                    openGroup(group)
                } label: {
                    HStack(spacing: 12) {
                        ProfileImageView(
                            photo: group.photo?.small,
                            minithumbnail: group.photo?.minithumbnail,
                            title: group.title,
                            userId: group.id,
                            fontSize: 18,
                        )
                        .frame(width: 44, height: 44)
                        .accessibilityHidden(true)

                        Text(group.title)
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
        // Declared here (not on the ancestor ChatInfoView) so it stacks directly on top of this
        // screen - see the matching comment in ChatInfoMembersView.
        .navigationDestination(item: $pushedChat) { customChat in
            ChatView(customChat: customChat, backButtonTitleOverride: "Groups in Common")
        }
        .alert("Can't Open Chat", isPresented: errorIsPresented) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Private

    @State private var errorMessage: String?
    @State private var groups = [Chat]()
    @State private var hasMore = true
    @State private var isLoading = true
    @State private var nextOffsetChatId: Int64 = 0
    @State private var pushedChat: CustomChat?

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

    private func openGroup(_ resolvedChat: Chat) {
        Task {
            guard let customChat = await RootVM.shared.getCustomChat(from: resolvedChat.id) else {
                errorMessage = "This chat is private or unavailable."
                return
            }
            pushedChat = customChat
        }
    }

    private func loadGroups() async {
        let page = await TelegramChatInfoLoader(service: service).loadCommonGroups(
            userId: userId,
            offsetChatId: 0,
        )
        groups = page.groups
        hasMore = page.hasMore
        nextOffsetChatId = page.nextOffsetChatId
        isLoading = false
    }

    private func loadNextPage() {
        guard !isLoading, hasMore else { return }
        isLoading = true
        Task {
            let page = await TelegramChatInfoLoader(service: service).loadCommonGroups(
                userId: userId,
                offsetChatId: nextOffsetChatId,
            )
            let knownIds = Set(groups.map(\.id))
            groups.append(contentsOf: page.groups.filter { !knownIds.contains($0.id) })
            hasMore = page.hasMore
            nextOffsetChatId = page.nextOffsetChatId
            isLoading = false
        }
    }
}
