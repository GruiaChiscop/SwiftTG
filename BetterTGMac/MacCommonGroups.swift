// MacCommonGroups.swift

import SwiftUI
import TDLibKit

// MARK: - MacCommonGroup

struct MacCommonGroup: Identifiable {
    let chat: Chat

    var id: Int64 { chat.id }
}

// MARK: - MacCommonGroupsPage

struct MacCommonGroupsPage {
    let groups: [MacCommonGroup]
    let hasMore: Bool
    let nextOffsetChatId: Int64
}

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
                ForEach(groups) { group in
                    Button {
                        dismiss()
                        onSelect(group.chat)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: ChatListItemKind(group.chat.type).systemImage)
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            Text(group.chat.title)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens this group")
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
    @State private var groups = [MacCommonGroup]()
    @State private var isLoading = true
    @State private var hasMore = true
    @State private var nextOffsetChatId: Int64 = 0

    private func loadGroups() async {
        let page = await model.loadCommonGroupsPage(userId: userId, offsetChatId: 0)
        groups = page.groups
        hasMore = page.hasMore
        nextOffsetChatId = page.nextOffsetChatId
        isLoading = false
    }

    private func loadNextPage() {
        guard !isLoading, hasMore else { return }
        isLoading = true
        Task {
            let page = await model.loadCommonGroupsPage(userId: userId, offsetChatId: nextOffsetChatId)
            let knownIds = Set(groups.map(\.id))
            groups.append(contentsOf: page.groups.filter { !knownIds.contains($0.id) })
            hasMore = page.hasMore
            nextOffsetChatId = page.nextOffsetChatId
            isLoading = false
        }
    }
}

extension MacSessionModel {
    func loadCommonGroupsPage(userId: Int64, offsetChatId: Int64) async -> MacCommonGroupsPage {
        guard !Task.isCancelled,
              let page = try? await service.getGroupsInCommon(
                  limit: 50,
                  offsetChatId: offsetChatId,
                  userId: userId,
              )
        else { return MacCommonGroupsPage(groups: [], hasMore: false, nextOffsetChatId: offsetChatId) }

        let service = service
        let resolved = await withTaskGroup(of: (Int, MacCommonGroup?).self) { group in
            for (index, chatId) in page.chatIds.enumerated() {
                group.addTask {
                    guard !Task.isCancelled, let chat = try? await service.getChat(chatId: chatId) else {
                        return (index, nil)
                    }
                    return (index, MacCommonGroup(chat: chat))
                }
            }
            var collected = [(index: Int, group: MacCommonGroup)]()
            for await (index, commonGroup) in group {
                guard let commonGroup else { continue }
                collected.append((index, commonGroup))
            }
            return collected
        }
        return MacCommonGroupsPage(
            groups: resolved.sorted { $0.index < $1.index }.map(\.group),
            hasMore: page.chatIds.count == 50,
            nextOffsetChatId: page.chatIds.last ?? offsetChatId,
        )
    }
}
