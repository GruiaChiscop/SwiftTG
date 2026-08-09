// ForumTopicsListView.swift

import SwiftUI
import TDLibKit

// MARK: - ForumTopicsListView

/// Shown instead of `ChatView` when opening a forum-enabled supergroup (`Supergroup.isForum`) -
/// mirrors Telegram-iOS's behavior of listing topics first rather than a flat message stream.
/// Tapping a topic pushes a `ChatView` scoped to it via `messageTopic: .messageTopicForum(...)`.
struct ForumTopicsListView: View {
    // MARK: Internal

    let customChat: CustomChat
    let service: any TelegramService

    var body: some View {
        List {
            if topics.isEmpty, isLoading {
                HStack {
                    Spacer()
                    ProgressView("Loading topics…")
                    Spacer()
                }
            } else if topics.isEmpty, let errorMessage {
                ContentUnavailableView(
                    "Couldn't Load Topics",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage),
                )
            } else if topics.isEmpty {
                ContentUnavailableView("No Topics", systemImage: "bubble.left.and.bubble.right")
            }

            ForEach(topics, id: \.info.forumTopicId) { topic in
                Button {
                    pushedTopic = topic
                } label: {
                    topicRow(topic)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accessibilityDescription(for: topic))
                .accessibilityActions {
                    Button(topic.isPinned ? "Unpin" : "Pin") { togglePinned(topic) }
                    Button(topic.info.isClosed ? "Reopen" : "Close") { toggleClosed(topic) }
                    if !topic.info.isGeneral {
                        Button("Edit") { editedTopic = topic.info }
                        Button("Delete", role: .destructive) { topicPendingDeletion = topic }
                    }
                }
                .swipeActions(edge: .trailing) {
                    if !topic.info.isGeneral {
                        Button("Delete", role: .destructive) { topicPendingDeletion = topic }
                    }
                    Button(topic.info.isClosed ? "Reopen" : "Close") { toggleClosed(topic) }
                        .tint(.orange)
                }
                .swipeActions(edge: .leading) {
                    Button(topic.isPinned ? "Unpin" : "Pin") { togglePinned(topic) }
                        .tint(.indigo)
                }
                .contextMenu {
                    Button(topic.isPinned ? "Unpin" : "Pin", systemImage: topic.isPinned ? "pin.slash" : "pin") {
                        togglePinned(topic)
                    }
                    Button(
                        topic.info.isClosed ? "Reopen" : "Close",
                        systemImage: topic.info.isClosed ? "lock.open" : "lock",
                    ) {
                        toggleClosed(topic)
                    }
                    if !topic.info.isGeneral {
                        Button("Edit", systemImage: "pencil") { editedTopic = topic.info }
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            topicPendingDeletion = topic
                        }
                    }
                }
            }

            if hasMore, !topics.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .onAppear { loadNextPage() }
            }
        }
        .listStyle(.plain)
        .navigationTitle(customChat.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Topic", systemImage: "plus") { showsCreateComposer = true }
            }
        }
        // Declared here (not on an ancestor) so it stacks directly on top of this screen - see
        // the same note in ChatInfoDetailViews.swift's ChatInfoMembersView.
        .navigationDestination(item: $pushedTopic) { topic in
            ChatView(
                customChat: customChat,
                messageTopic: .messageTopicForum(MessageTopicForum(forumTopicId: topic.info.forumTopicId)),
                backButtonTitleOverride: customChat.displayTitle,
            )
        }
        .sheet(isPresented: $showsCreateComposer) {
            TelegramForumTopicComposerView(service: service, existingTopic: nil) { draft in
                _ = try await TelegramForumTopicSending.create(
                    service: service,
                    chatId: customChat.chat.id,
                    draft: draft,
                )
                await reload(force: true)
            } iconPreview: { icon in
                TelegramStickerView(sticker: icon, service: service, maxSide: 44, playsAnimation: false)
            }
        }
        .sheet(isPresented: editComposerIsPresented) {
            if let topicInfo = editedTopic {
                TelegramForumTopicComposerView(service: service, existingTopic: topicInfo) { draft in
                    try await TelegramForumTopicSending.edit(
                        service: service,
                        chatId: customChat.chat.id,
                        forumTopicId: topicInfo.forumTopicId,
                        draft: draft,
                    )
                    await reload(force: true)
                } iconPreview: { icon in
                    TelegramStickerView(sticker: icon, service: service, maxSide: 44, playsAnimation: false)
                }
            }
        }
        .alert("Delete Topic", isPresented: deletionAlertIsPresented, presenting: topicPendingDeletion) { topic in
            Button("Delete", role: .destructive) { delete(topic) }
            Button("Cancel", role: .cancel) {}
        } message: { topic in
            Text("This will permanently delete \"\(topic.info.name)\" and all of its messages.")
        }
        .alert("Error", isPresented: errorIsPresented) {
            Button("OK") {}
        } message: {
            Text(actionErrorMessage ?? "")
        }
        .task { await reload() }
        .refreshable { await reload(force: true) }
    }

    // MARK: Private

    private static let pageSize = 100

    @State private var topics = [ForumTopic]()
    @State private var isLoading = false
    @State private var hasMore = true
    @State private var errorMessage: String?
    @State private var pushedTopic: ForumTopic?
    @State private var nextOffsetDate = 0
    @State private var nextOffsetForumTopicId = 0
    @State private var nextOffsetMessageId: Int64 = 0
    @State private var loadGeneration: UInt64 = 0
    @State private var showsCreateComposer = false
    @State private var editedTopic: ForumTopicInfo?
    @State private var topicPendingDeletion: ForumTopic?
    @State private var actionErrorMessage: String?

    private var editComposerIsPresented: Binding<Bool> {
        Binding(
            get: { editedTopic != nil },
            set: {
                isPresented in if !isPresented {
                    editedTopic = nil
                }
            },
        )
    }

    private var deletionAlertIsPresented: Binding<Bool> {
        Binding(
            get: { topicPendingDeletion != nil },
            set: {
                isPresented in if !isPresented {
                    topicPendingDeletion = nil
                }
            },
        )
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { actionErrorMessage != nil },
            set: {
                isPresented in if !isPresented {
                    actionErrorMessage = nil
                }
            },
        )
    }

    private func topicRow(_ topic: ForumTopic) -> some View {
        HStack(spacing: 12) {
            topicIcon(topic)
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    if topic.info.isClosed {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }

                    Text(topic.info.name)
                        .font(.headline)
                        .fontWeight(topic.unreadCount > 0 ? .semibold : .regular)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    if let lastMessage = topic.lastMessage {
                        Text(telegramChatListTimestamp(lastMessage.date))
                            .font(.caption)
                            .foregroundStyle(topic.unreadCount > 0
                                ? Color
                                    .accentColor
                                : Color(uiColor: .secondaryLabel))
                    }
                }

                HStack(spacing: 7) {
                    if let lastMessage = topic.lastMessage {
                        Text(telegramChatListMessageDescription(lastMessage))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    if topic.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    if topic.unreadCount > 0 {
                        Text("\(topic.unreadCount)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .frame(minWidth: 24, minHeight: 22)
                            .background(.tint, in: Capsule())
                    }
                }
            }
        }
        .lineLimit(1)
        .padding(.vertical, 4)
    }

    private func topicIcon(_ topic: ForumTopic) -> some View {
        Circle()
            .fill(Color(topicIconRGB: topic.info.icon.color))
            .overlay {
                Text(String(topic.info.name.first ?? "#"))
                    .font(.headline)
                    .foregroundStyle(.white)
            }
    }

    private func togglePinned(_ topic: ForumTopic) {
        Task {
            do {
                _ = try await service.toggleForumTopicIsPinned(
                    chatId: customChat.chat.id,
                    forumTopicId: topic.info.forumTopicId,
                    isPinned: !topic.isPinned,
                )
                await reload(force: true)
            } catch {
                actionErrorMessage = telegramErrorDescription(error)
            }
        }
    }

    private func toggleClosed(_ topic: ForumTopic) {
        Task {
            do {
                _ = try await service.toggleForumTopicIsClosed(
                    chatId: customChat.chat.id,
                    forumTopicId: topic.info.forumTopicId,
                    isClosed: !topic.info.isClosed,
                )
                await reload(force: true)
            } catch {
                actionErrorMessage = telegramErrorDescription(error)
            }
        }
    }

    private func delete(_ topic: ForumTopic) {
        Task {
            do {
                _ = try await service.deleteForumTopic(
                    chatId: customChat.chat.id,
                    forumTopicId: topic.info.forumTopicId,
                )
                await reload(force: true)
            } catch {
                actionErrorMessage = telegramErrorDescription(error)
            }
        }
    }

    private func accessibilityDescription(for topic: ForumTopic) -> String {
        var parts = [topic.info.name]
        if topic.info.isClosed {
            parts.append("Closed")
        }
        if topic.isPinned {
            parts.append("Pinned")
        }
        if topic.unreadCount > 0 {
            parts.append("\(topic.unreadCount) unread")
        }
        if let lastMessage = topic.lastMessage {
            parts.append(telegramChatListMessageDescription(lastMessage))
        }
        return parts.joined(separator: ", ")
    }

    private func reload(force: Bool = false) async {
        guard force || topics.isEmpty else { return }
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let result = try await service.getForumTopics(
                chatId: customChat.chat.id,
                limit: Self.pageSize,
                offsetDate: 0,
                offsetForumTopicId: 0,
                offsetMessageId: 0,
                query: nil,
            )
            guard generation == loadGeneration else { return }
            topics = result.topics
            nextOffsetDate = result.nextOffsetDate
            nextOffsetForumTopicId = result.nextOffsetForumTopicId
            nextOffsetMessageId = result.nextOffsetMessageId
            hasMore = result.topics.count >= Self.pageSize
        } catch {
            guard generation == loadGeneration, !Task.isCancelled else { return }
            errorMessage = telegramErrorDescription(error)
        }
    }

    private func loadNextPage() {
        guard !isLoading, hasMore else { return }
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true

        Task {
            defer { isLoading = false }
            do {
                let result = try await service.getForumTopics(
                    chatId: customChat.chat.id,
                    limit: Self.pageSize,
                    offsetDate: nextOffsetDate,
                    offsetForumTopicId: nextOffsetForumTopicId,
                    offsetMessageId: nextOffsetMessageId,
                    query: nil,
                )
                guard generation == loadGeneration else { return }
                topics.append(contentsOf: result.topics)
                nextOffsetDate = result.nextOffsetDate
                nextOffsetForumTopicId = result.nextOffsetForumTopicId
                nextOffsetMessageId = result.nextOffsetMessageId
                hasMore = result.topics.count >= Self.pageSize
            } catch {
                guard generation == loadGeneration else { return }
                hasMore = false
            }
        }
    }
}
