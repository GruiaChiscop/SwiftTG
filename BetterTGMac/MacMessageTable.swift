import SwiftUI
import TDLibKit

// MARK: - MacMessageTable

/// The conversation is intentionally a native SwiftUI list. Keeping the historical type name
/// avoids churn in the project file while removing the NSTableView/NSHostingView bridge that used
/// to wrap every message row.
struct MacMessageTable: View {
    @Bindable var model: MacSessionModel

    let chat: ChatListItemState
    let unreadBoundaryMessageId: Int64?
    let shouldFollowLatestMessage: Bool
    @Binding var isAtBottom: Bool

    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(Array(model.messages.orderedMessageIds.enumerated()), id: \.element) { index, messageId in
                    if let message = model.messages.messages[messageId] {
                        if startsNewDay(at: index) {
                            MacMessageDayHeader(title: telegramMessageDayHeading(message.date))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
                        if unreadBoundaryMessageId == messageId {
                            MacUnreadMessagesHeader(count: model.openedUnreadCount)
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
                        MacMessageRow(
                            model: model,
                            message: message,
                            lastReadOutboxMessageId: chat.lastReadOutboxMessageId,
                        )
                        .id(messageId)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .onAppear {
                            guard messageId == model.messages.orderedMessageIds.first,
                                  hasPositionedInitialMessages,
                                  !model.isLoadingMessages,
                                  !model.isLoadingOlderMessages
                            else { return }
                            beginLoadingOlderMessages()
                        }
                        .onScrollVisibilityChange(threshold: 0.2) { isVisible in
                            guard messageId == model.messages.orderedMessageIds.last else { return }
                            isAtBottom = isVisible
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .onChange(of: model.messages.version) {
                handleMessageChange(using: proxy)
            }
            .onChange(of: model.isLoadingMessages) { _, isLoading in
                guard !isLoading,
                      model.navigationTargetMessageId == nil,
                      let lastMessageId = model.messages.orderedMessageIds.last
                else { return }
                positionAtBottom(lastMessageId, using: proxy)
            }
            .onChange(of: model.navigationTargetMessageId) { _, messageId in
                guard let messageId, model.messages.messages[messageId] != nil else { return }
                positionSearchResult(messageId, using: proxy)
            }
            .onChange(of: chat.chatId) {
                historyAnchorMessageId = nil
                hasPositionedInitialMessages = false
                isAtBottom = false
                model.latestHistoryTargetMessageId = nil
            }
        }
    }

    @State private var historyAnchorMessageId: Int64?
    @State private var hasPositionedInitialMessages = false

    private func startsNewDay(at index: Int) -> Bool {
        let ids = model.messages.orderedMessageIds
        guard ids.indices.contains(index), let message = model.messages.messages[ids[index]] else { return false }
        guard index > ids.startIndex, let previous = model.messages.messages[ids[index - 1]] else { return true }
        return !Calendar.autoupdatingCurrent.isDate(
            Date(timeIntervalSince1970: TimeInterval(message.date)),
            inSameDayAs: Date(timeIntervalSince1970: TimeInterval(previous.date)),
        )
    }

    private func handleMessageChange(using proxy: ScrollViewProxy) {
        if let latestMessageId = model.latestHistoryTargetMessageId,
           model.messages.messages[latestMessageId] != nil
        {
            positionAtLatestHistory(model.messages.orderedMessageIds.last ?? latestMessageId, using: proxy)
        } else if let targetMessageId = model.navigationTargetMessageId,
                  model.messages.messages[targetMessageId] != nil
        {
            positionSearchResult(targetMessageId, using: proxy)
        } else if let anchorMessageId = historyAnchorMessageId {
            if model.messages.orderedMessageIds.first != anchorMessageId {
                proxy.scrollTo(anchorMessageId, anchor: .top)
                historyAnchorMessageId = nil
            }
        } else if !hasPositionedInitialMessages,
                  let lastMessageId = model.messages.orderedMessageIds.last
        {
            positionAtBottom(lastMessageId, using: proxy)
        } else if shouldFollowLatestMessage,
                  let lastMessageId = model.messages.orderedMessageIds.last
        {
            proxy.scrollTo(lastMessageId, anchor: .bottom)
        }
    }

    private func positionSearchResult(_ messageId: Int64, using proxy: ScrollViewProxy) {
        proxy.scrollTo(messageId, anchor: .center)
        model.navigationTargetMessageId = nil
        hasPositionedInitialMessages = true
    }

    private func positionAtBottom(_ messageId: Int64, using proxy: ScrollViewProxy) {
        Task { @MainActor in
            await Task.yield()
            await Task.yield()
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                proxy.scrollTo(messageId, anchor: .bottom)
            }
            hasPositionedInitialMessages = true
            isAtBottom = true
        }
    }

    private func positionAtLatestHistory(_ messageId: Int64, using proxy: ScrollViewProxy) {
        proxy.scrollTo(messageId, anchor: .bottom)
        isAtBottom = true
        hasPositionedInitialMessages = true
        model.latestHistoryTargetMessageId = nil
    }

    private func beginLoadingOlderMessages() {
        guard historyAnchorMessageId == nil,
              let anchorMessageId = model.messages.orderedMessageIds.first
        else { return }
        historyAnchorMessageId = anchorMessageId
        Task {
            if await !model.loadOlderMessages() {
                historyAnchorMessageId = nil
            }
        }
    }
}

// MARK: - MacMessageDayHeader

private struct MacMessageDayHeader: View {
    let title: String

    var body: some View {
        HStack {
            Spacer()
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.regularMaterial, in: Capsule())
            Spacer()
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - MacUnreadMessagesHeader

private struct MacUnreadMessagesHeader: View {
    let count: Int

    var body: some View {
        HStack(spacing: 10) {
            Divider()
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)
            Divider()
        }
        .frame(height: 24)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isHeader)
    }

    private var title: String {
        "\(count) unread \(count == 1 ? "message" : "messages")"
    }
}
