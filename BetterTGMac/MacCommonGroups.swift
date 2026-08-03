// MacCommonGroups.swift

import SwiftUI
import TDLibKit

// MARK: - MacCommonGroupsView

struct MacCommonGroupsView: View {
    // MARK: Internal

    @Bindable var model: MacSessionModel

    let userId: Int64
    let expectedCount: Int
    let onSelect: (Chat) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(groups, id: \.id) { group in
                    Button {
                        dismiss()
                        onSelect(group)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: ChatListItemKind(group.type).systemImage)
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            Text(group.title)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
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
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 460, idealWidth: 540, minHeight: 480, idealHeight: 640)
        .task { await loadGroups() }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var groups = [Chat]()
    @State private var isLoading = true
    @State private var hasMore = true
    @State private var nextOffsetChatId: Int64 = 0

    private func loadGroups() async {
        let page = await TelegramChatInfoLoader(service: model.service).loadCommonGroups(
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
            let page = await TelegramChatInfoLoader(service: model.service).loadCommonGroups(
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
