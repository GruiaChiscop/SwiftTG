// MacMessageTable.swift

import SwiftUI
import TDLibKit

// MARK: - MacMessageTable

/// The conversation is intentionally a native SwiftUI list. Keeping the historical type name
/// avoids churn in the project file while removing the NSTableView/NSHostingView bridge that used
/// to wrap every message row.
struct MacMessageTable: View {
    // MARK: Internal

    @Bindable var model: MacSessionModel

    let chat: ChatListItemState
    let unreadBoundaryMessageId: Int64?
    let shouldFollowLatestMessage: Bool

    @Binding var isAtBottom: Bool

    var body: some View {
        List(messageRows, selection: $selectedRowId) { row in
            switch row.kind {
            case .day(let title):
                MacMessageDayHeader(title: title)
                    .tag(row.id)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

            case .unread(let count):
                MacUnreadMessagesHeader(count: count)
                    .tag(row.id)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

            case .message(let messageId):
                if let message = model.messages.messages[messageId] {
                    MacMessageRow(
                        model: model,
                        message: message,
                        lastReadOutboxMessageId: chat.lastReadOutboxMessageId,
                    )
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
        .scrollPosition($scrollPosition)
        .accessibilityLabel("Messages")
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.visibleRect.maxY >= geometry.contentSize.height - 20
        } action: { _, newIsAtBottom in
            isAtBottom = newIsAtBottom
        }
        .onChange(of: model.messages.version) {
            handleMessageChange()
        }
        .onChange(of: model.isLoadingMessages) { _, isLoading in
            guard !isLoading,
                  model.navigationTargetMessageId == nil,
                  let lastMessageId = model.messages.orderedMessageIds.last
            else { return }
            positionAtBottom(lastMessageId)
        }
        .onChange(of: model.navigationTargetMessageId) { _, messageId in
            guard let messageId, model.messages.messages[messageId] != nil else { return }
            positionSearchResult(messageId)
        }
        .task(id: selectedRowId) {
            guard case .message(let messageId) = selectedRowId,
                  let message = model.messages.messages[messageId]
            else { return }
            await model.loadAvailableReactions(for: message)
        }
        .onChange(of: chat.chatId) {
            selectedRowId = nil
            historyAnchorMessageId = nil
            scrollPosition = ScrollPosition(idType: MacMessageListRow.ID.self)
            hasPositionedInitialMessages = false
            isAtBottom = false
            model.latestHistoryTargetMessageId = nil
        }
    }

    // MARK: Private

    @State private var historyAnchorMessageId: Int64?
    @State private var hasPositionedInitialMessages = false
    @State private var selectedRowId: MacMessageListRow.ID?
    @State private var scrollPosition = ScrollPosition(idType: MacMessageListRow.ID.self)

    private var messageRows: [MacMessageListRow] {
        var rows = [MacMessageListRow]()
        rows.reserveCapacity(model.messages.orderedMessageIds.count + 2)
        let calendar = Calendar.autoupdatingCurrent
        var previousMessage: Message?

        for messageId in model.messages.orderedMessageIds {
            guard let message = model.messages.messages[messageId] else { continue }

            let startsNewDay = previousMessage.map {
                !calendar.isDate(
                    Date(timeIntervalSince1970: TimeInterval(message.date)),
                    inSameDayAs: Date(timeIntervalSince1970: TimeInterval($0.date)),
                )
            } ?? true
            if startsNewDay {
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
            previousMessage = message
        }

        return rows
    }

    private func handleMessageChange() {
        if let latestMessageId = model.latestHistoryTargetMessageId,
           model.messages.messages[latestMessageId] != nil
        {
            positionAtLatestHistory(model.messages.orderedMessageIds.last ?? latestMessageId)
        } else if let targetMessageId = model.navigationTargetMessageId,
                  model.messages.messages[targetMessageId] != nil
        {
            positionSearchResult(targetMessageId)
        } else if let anchorMessageId = historyAnchorMessageId {
            if model.messages.orderedMessageIds.first != anchorMessageId {
                scrollPosition.scrollTo(id: MacMessageListRow.ID.message(anchorMessageId), anchor: .top)
                historyAnchorMessageId = nil
            }
        } else if !model.isLoadingMessages,
                  !hasPositionedInitialMessages,
                  let lastMessageId = model.messages.orderedMessageIds.last
        {
            positionAtBottom(lastMessageId)
        } else if shouldFollowLatestMessage,
                  let lastMessageId = model.messages.orderedMessageIds.last
        {
            scrollPosition.scrollTo(id: MacMessageListRow.ID.message(lastMessageId), anchor: .bottom)
        }
    }

    private func positionSearchResult(_ messageId: Int64) {
        selectedRowId = .message(messageId)
        scrollPosition.scrollTo(id: MacMessageListRow.ID.message(messageId), anchor: .center)
        model.navigationTargetMessageId = nil
        hasPositionedInitialMessages = true
    }

    private func positionAtBottom(_ messageId: Int64) {
        guard !hasPositionedInitialMessages else { return }
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            scrollPosition.scrollTo(id: MacMessageListRow.ID.message(messageId), anchor: .bottom)
        }
        hasPositionedInitialMessages = true
        isAtBottom = true
    }

    private func positionAtLatestHistory(_ messageId: Int64) {
        selectedRowId = .message(messageId)
        scrollPosition.scrollTo(id: MacMessageListRow.ID.message(messageId), anchor: .bottom)
        isAtBottom = true
        hasPositionedInitialMessages = true
        model.latestHistoryTargetMessageId = nil
    }

    private func beginLoadingOlderMessages() {
        guard historyAnchorMessageId == nil,
              let anchorMessageId = model.messages.orderedMessageIds.first
        else { return }
        historyAnchorMessageId = anchorMessageId
        let chatId = chat.chatId
        Task {
            let loadedMessages = await model.loadOlderMessages()
            guard model.openedChatId == chatId,
                  historyAnchorMessageId == anchorMessageId
            else { return }
            if !loadedMessages {
                historyAnchorMessageId = nil
            }
        }
    }
}

// MARK: - MacMessageListRow

private struct MacMessageListRow: Identifiable {
    enum ID: Hashable, Sendable {
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
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - MacUnreadMessagesHeader

private struct MacUnreadMessagesHeader: View {
    // MARK: Internal

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
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: Private

    private var title: String {
        "\(count) unread \(count == 1 ? "message" : "messages")"
    }
}
