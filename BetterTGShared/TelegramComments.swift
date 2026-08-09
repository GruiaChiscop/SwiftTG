// TelegramComments.swift

import SwiftUI
@preconcurrency import TDLibKit

// MARK: - TelegramCommentsBar

/// The "N Comments" row shown under a channel post that has a linked discussion group - matches
/// where official Telegram puts it, at the bottom of the post rather than as a separate action.
struct TelegramCommentsBar: View {
    let replyCount: Int
    /// Set while the tap target is resolving the discussion thread before navigating - matches
    /// Telegram-iOS, which preloads the thread and only then pushes the comments screen, rather
    /// than opening a screen that fills in after the fact.
    var isLoading = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: "bubble.left")
                Text(replyCount > 0 ? "\(replyCount) Comment\(replyCount == 1 ? "" : "s")" : "Leave a Comment")
                    .font(.footnote.weight(.medium))
                Spacer()
                if isLoading {
                    ProgressView()
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
        .disabled(isLoading)
    }
}

// MARK: - TelegramCommentsView

/// Comments on a channel post live as a message thread in the channel's linked discussion
/// supergroup - `getMessageThread` resolves which one and where the thread starts, matching how
/// TDLib itself documents the flow (`InternalLinkTypeMessage`'s reply-count use case). This is
/// deliberately its own light-weight message list rather than reusing `ChatVM`/`ChatView`: those
/// are built around a *whole chat's* history and every message-composer feature (attachments,
/// polls, scheduling...), all tightly coupled to a single `chatId`. Threading thread-scoping
/// through all of that would touch a lot of perf-sensitive, already-battle-tested surface for a
/// feature that's fundamentally simpler: read a bounded list of replies, post a plain-text one.
/// Live updates (new/edited/deleted comments, typing) come from the same global
/// `service.updatePublisher` every other live surface in the app already reads from - filtered
/// down to this specific thread - not from `ChatVM`'s per-chat store.
struct TelegramCommentsView: View {
    // MARK: Lifecycle

    init(service: any TelegramService, channelChatId: Int64, messageId: Int64) {
        self.service = service
        self.channelChatId = channelChatId
        self.messageId = messageId
    }

    // MARK: Internal

    let service: any TelegramService
    let channelChatId: Int64
    let messageId: Int64

    var body: some View {
        NavigationStack {
            List {
                if isLoading, comments.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else if comments.isEmpty {
                    ContentUnavailableView(
                        "No Comments Yet",
                        systemImage: "bubble.left",
                        description: Text("Be the first to leave a comment."),
                    )
                } else {
                    if !hasReachedBeginning {
                        HStack {
                            Spacer()
                            if isLoadingOlder {
                                ProgressView()
                            } else {
                                Button("Load Earlier Comments") {
                                    Task { await loadOlderComments() }
                                }
                                .font(.footnote)
                            }
                            Spacer()
                        }
                    }
                    ForEach(comments, id: \.id) { message in
                        commentRow(message)
                    }
                }
            }
            .listStyle(.plain)
            .refreshable { await refresh() }
            .navigationTitle("Comments")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    VStack(alignment: .leading, spacing: 0) {
                        if let typingText {
                            Text(typingText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.top, 6)
                        }
                        composer
                    }
                }
        }
        .frame(minWidth: 380, minHeight: 480)
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await loadThread()
        }
        .onReceive(service.updatePublisher) { update in
            handle(update)
        }
        .alert("Comments Error", isPresented: errorIsPresented) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    @State private var comments = [Message]()
    @State private var commentText = ""
    @State private var discussionChatId: Int64?
    @State private var errorMessage: String?
    @State private var hasLoaded = false
    @State private var hasReachedBeginning = false
    @State private var isLoading = false
    @State private var isLoadingOlder = false
    @State private var isSending = false
    @State private var messageThreadId: Int64?
    @State private var senderNames = [String: String]()
    @State private var typingActions = [MessageSender: ChatAction]()

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

    /// A thread-scoped equivalent of the plain `chatId` check most `Update` handling in the app
    /// filters on - each channel post's comments live in the *same* discussion group, distinguished
    /// only by `topicId`, so every handler here needs both.
    private var thisThreadTopic: MessageTopic? {
        guard let messageThreadId else { return nil }
        return .messageTopicThread(MessageTopicThread(messageThreadId: messageThreadId))
    }

    private var typingText: String? {
        let typingNames = typingActions
            .filter {
                if case .chatActionTyping = $0.value {
                    true
                } else {
                    false
                }
            }
            .compactMap { senderNames[senderKey($0.key)] }
        guard !typingNames.isEmpty else { return nil }
        return typingNames.count == 1
            ? "\(typingNames[0]) is typing…"
            : "\(typingNames.joined(separator: ", ")) are typing…"
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField("Add a comment…", text: $commentText, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.quaternary, in: Capsule())

            Button {
                Task { await sendComment() }
            } label: {
                if isSending {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
            }
            .disabled(isSending || commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(10)
        .background(.bar)
    }

    private func commentRow(_ message: Message) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(senderNames[senderKey(message.senderId)] ?? "…")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(
                    Date(timeIntervalSince1970: TimeInterval(message.date)),
                    format: .dateTime.day().month().hour().minute(),
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let formattedText = telegramMessageFormattedText(message) {
                #if os(iOS)
                MessageTextView(formattedText: formattedText)
                #else
                MacFormattedTextView(formattedText: formattedText)
                #endif
            } else {
                Text(telegramMessageContentDescription(message))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .task(id: message.id) { await resolveSenderName(for: message.senderId) }
    }

    private func senderKey(_ sender: MessageSender) -> String {
        switch sender {
        case .messageSenderUser(let value): "user:\(value.userId)"
        case .messageSenderChat(let value): "chat:\(value.chatId)"
        }
    }

    @MainActor private func resolveSenderName(for sender: MessageSender) async {
        let key = senderKey(sender)
        guard senderNames[key] == nil else { return }
        switch sender {
        case .messageSenderUser(let value):
            guard let user = try? await service.getUser(userId: value.userId) else { return }
            senderNames[key] = telegramUserDisplayName(user)
        case .messageSenderChat(let value):
            guard let chat = try? await service.getChat(chatId: value.chatId) else { return }
            senderNames[key] = chat.title
        }
    }

    /// Routes the four update kinds a live thread needs to react to - filtering every one on both
    /// `discussionChatId` and `thisThreadTopic`, since the same discussion group carries comment
    /// threads for every other post in the channel too.
    private func handle(_ update: Update) {
        guard let discussionChatId, let thisThreadTopic else { return }
        switch update {
        case .updateNewMessage(let value):
            guard value.message.chatId == discussionChatId, value.message.topicId == thisThreadTopic else { return }
            guard !comments.contains(where: { $0.id == value.message.id }) else { return }
            comments.append(value.message)
            comments.sort { $0.id < $1.id }
            Task { await resolveSenderName(for: value.message.senderId) }

        case .updateMessageContent(let value):
            guard value.chatId == discussionChatId, comments.contains(where: { $0.id == value.messageId }) else {
                return
            }
            // Refetches the whole message rather than splicing `newContent` into the cached copy
            // by hand - `Message` carries dozens of fields (edit date, reactions, etc.) that would
            // otherwise go stale.
            Task {
                guard let refreshed = try? await service.getMessage(
                    chatId: discussionChatId,
                    messageId: value.messageId,
                ),
                    let index = comments.firstIndex(where: { $0.id == value.messageId })
                else { return }
                comments[index] = refreshed
            }

        case .updateDeleteMessages(let value):
            guard value.chatId == discussionChatId else { return }
            comments.removeAll { value.messageIds.contains($0.id) }

        case .updateChatAction(let value):
            guard value.chatId == discussionChatId, value.topicId == thisThreadTopic else { return }
            if case .chatActionCancel = value.action {
                typingActions[value.senderId] = nil
            } else {
                typingActions[value.senderId] = value.action
                Task { await resolveSenderName(for: value.senderId) }
            }

        default:
            break
        }
    }

    @MainActor private func loadThread() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let thread = try await service.getMessageThread(chatId: channelChatId, messageId: messageId)
            discussionChatId = thread.chatId
            messageThreadId = thread.messageThreadId
            comments = thread.messages.sorted { $0.id < $1.id }
            hasReachedBeginning = thread.messages.isEmpty
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }

    @MainActor private func loadOlderComments() async {
        guard let discussionChatId, let messageThreadId, let oldestId = comments.first?.id else { return }
        isLoadingOlder = true
        defer { isLoadingOlder = false }
        guard let history = try? await service.getMessageThreadHistory(
            chatId: discussionChatId,
            fromMessageId: oldestId,
            limit: 30,
            messageId: messageThreadId,
            offset: 0,
        ), let page = history.messages, !page.isEmpty else {
            hasReachedBeginning = true
            return
        }
        let existingIds = Set(comments.map(\.id))
        let newMessages = page.filter { !existingIds.contains($0.id) }.sorted { $0.id < $1.id }
        comments.insert(contentsOf: newMessages, at: 0)
        if newMessages.isEmpty {
            hasReachedBeginning = true
        }
    }

    @MainActor private func refresh() async {
        guard let discussionChatId, let messageThreadId else {
            await loadThread()
            return
        }
        guard let history = try? await service.getMessageThreadHistory(
            chatId: discussionChatId,
            fromMessageId: 0,
            limit: 30,
            messageId: messageThreadId,
            offset: 0,
        ), let page = history.messages else { return }
        let existingIds = Set(comments.map(\.id))
        let newMessages = page.filter { !existingIds.contains($0.id) }
        guard !newMessages.isEmpty else { return }
        comments = (comments + newMessages).sorted { $0.id < $1.id }
    }

    @MainActor private func sendComment() async {
        guard let discussionChatId, let messageThreadId else { return }
        let text = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        isSending = true
        defer { isSending = false }
        do {
            let sent = try await TelegramMessageSending.send(
                service: service,
                chatId: discussionChatId,
                contents: [TelegramMessageSending.textContent(FormattedText(entities: [], text: text))],
                replyTo: nil,
                topicId: .messageTopicThread(MessageTopicThread(messageThreadId: messageThreadId)),
            )
            commentText = ""
            comments.append(contentsOf: sent)
            comments.sort { $0.id < $1.id }
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }
}
