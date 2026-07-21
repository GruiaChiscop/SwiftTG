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
            List(messageRows, selection: $selectedRowId) { row in
                switch row.kind {
                case let .day(title):
                    MacMessageDayHeader(title: title)
                        .tag(row.id)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)

                case let .unread(count):
                    MacUnreadMessagesHeader(count: count)
                        .tag(row.id)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)

                case let .message(messageId):
                    if let message = model.messages.messages[messageId] {
                        MacMessageRow(
                            model: model,
                            message: message,
                            lastReadOutboxMessageId: chat.lastReadOutboxMessageId,
                        )
                        .id(messageId)
                        .tag(row.id)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .onAppear {
                            if messageId == model.messages.orderedMessageIds.first,
                               hasPositionedInitialMessages,
                               !model.isLoadingMessages,
                               !model.isLoadingOlderMessages
                            {
                                beginLoadingOlderMessages()
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .accessibilityLabel("Messages")
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.visibleRect.maxY >= geometry.contentSize.height - 20
            } action: { _, newIsAtBottom in
                isAtBottom = newIsAtBottom
            }
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
                selectedRowId = nil
                historyAnchorMessageId = nil
                hasPositionedInitialMessages = false
                isAtBottom = false
                model.latestHistoryTargetMessageId = nil
            }
        }
    }

    @State private var historyAnchorMessageId: Int64?
    @State private var hasPositionedInitialMessages = false
    @State private var selectedRowId: MacMessageListRow.ID?

    private var messageRows: [MacMessageListRow] {
        var rows: [MacMessageListRow] = []
        rows.reserveCapacity(model.messages.orderedMessageIds.count + 2)

        for (index, messageId) in model.messages.orderedMessageIds.enumerated() {
            guard let message = model.messages.messages[messageId] else { continue }

            if startsNewDay(at: index) {
                rows.append(
                    MacMessageListRow(
                        id: .day(messageId),
                        kind: .day(telegramMessageDayHeading(message.date)),
                    ),
                )
            }

            if unreadBoundaryMessageId == messageId {
                rows.append(
                    MacMessageListRow(
                        id: .unread(messageId),
                        kind: .unread(model.openedUnreadCount),
                    ),
                )
            }

            rows.append(MacMessageListRow(id: .message(messageId), kind: .message(messageId)))
        }

        return rows
    }

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
        selectedRowId = .message(messageId)
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
        selectedRowId = .message(messageId)
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

// MARK: - MacMessageListRow

private struct MacMessageListRow: Identifiable {
    enum ID: Hashable {
        case day(Int64)
        case unread(Int64)
        case message(Int64)
    }

    enum Kind {
        case day(String)
        case unread(Int)
        case message(Int64)
    }

    let id: ID
    let kind: Kind
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
