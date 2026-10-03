import AppKit
import SwiftUI
import TDLibKit

// MARK: - MacMessageTable

struct MacMessageTable: NSViewRepresentable {
    @Bindable var model: MacSessionModel

    let chat: ChatListItemState
    let unreadBoundaryMessageId: Int64?
    let shouldFollowLatestMessage: Bool
    @Binding var selectedMessageId: Int64?
    @Binding var isAtBottom: Bool
    let onLoadOlder: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = MessageNSTableView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Message"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .regular
        tableView.allowsEmptySelection = true
        tableView.allowsMultipleSelection = false
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.intercellSpacing = .zero
        tableView.usesAutomaticRowHeights = true
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        tableView.setAccessibilityLabel("Messages")

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        context.coordinator.tableView = tableView
        context.coordinator.scrollView = scrollView
        context.coordinator.startObservingScroll()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.update(scrollView: scrollView)
    }

    static func dismantleNSView(_: NSScrollView, coordinator: Coordinator) {
        coordinator.stopObservingScroll()
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        /// One entry per table row. Unread/day dividers get their own row - matching how SwiftUI's
        /// `List` gives iOS separate rows for free from a `@ViewBuilder` - rather than being stacked
        /// on top of a message's content inside a shared row/accessibility container.
        enum Row {
            case dayHeader(String)
            case unreadHeader(Int)
            case message(Int64, albumMessageIds: [Int64]?)

            var messageId: Int64? {
                if case .message(let id, _) = self { id } else { nil }
            }

            func containsMessage(_ id: Int64) -> Bool {
                guard case .message(let messageId, let albumMessageIds) = self else { return false }
                return messageId == id || albumMessageIds?.contains(id) == true
            }
        }

        var parent: MacMessageTable
        weak var tableView: MessageNSTableView?
        weak var scrollView: NSScrollView?

        private var messageIds = [Int64]()
        private var rows = [Row]()
        private var previousChatId: Int64?
        private var previousVersion: UInt64?
        private var previousIsLoadingMessages = false
        private var previousSelectedMessageId: Int64?
        private var previousUnreadBoundaryMessageId: Int64?
        private var hasPositionedInitialMessages = false
        private var scrollObserver: NSObjectProtocol?
        private var isRestoringScrollPosition = false

        init(parent: MacMessageTable) {
            self.parent = parent
        }

        func numberOfRows(in _: NSTableView) -> Int {
            rows.count
        }

        func tableView(_ tableView: NSTableView, viewFor _: NSTableColumn?, row: Int) -> NSView? {
            guard let entry = entry(at: row) else { return nil }

            let identifier = NSUserInterfaceItemIdentifier("HostedMessageCell")
            let cell: HostedMessageCell
            if let reused = tableView.makeView(withIdentifier: identifier, owner: nil) as? HostedMessageCell {
                cell = reused
            } else {
                cell = HostedMessageCell()
                cell.identifier = identifier
            }
            // Cells are reused across rows - reset before `setRootView` so a recycled cell never
            // exposes a stale message's accessibility label/children while the new row's `.task`
            // push (in `MacMessageRow`) is still in flight.
            cell.accessibilityBridge.reset()
            cell.setRootView(rowView(for: entry, accessibilityBridge: cell.accessibilityBridge))
            return cell
        }

        func tableView(_: NSTableView, rowViewForRow _: Int) -> NSTableRowView? {
            MessageTableRowView()
        }

        func tableView(_: NSTableView, shouldSelectRow row: Int) -> Bool {
            self.entry(at: row)?.messageId != nil
        }

        func tableViewSelectionDidChange(_ notification: Foundation.Notification) {
            guard let tableView = notification.object as? NSTableView,
                  let messageId = entry(at: tableView.selectedRow)?.messageId
            else { return }
            parent.selectedMessageId = messageId
        }

        func update(scrollView: NSScrollView) {
            guard let tableView else { return }
            let newIds = parent.model.messages.orderedMessageIds
            let chatChanged = previousChatId != parent.chat.chatId
            let versionChanged = previousVersion != parent.model.messages.version
            let loadingChanged = previousIsLoadingMessages != parent.model.isLoadingMessages
            let unreadBoundaryChanged = previousUnreadBoundaryMessageId != parent.unreadBoundaryMessageId

            if chatChanged {
                previousChatId = parent.chat.chatId
                previousVersion = nil
                previousIsLoadingMessages = parent.model.isLoadingMessages
                previousSelectedMessageId = nil
                previousUnreadBoundaryMessageId = nil
                hasPositionedInitialMessages = false
                messageIds = []
                rows = []
            }

            let selectionChanged = previousSelectedMessageId != parent.selectedMessageId
            guard chatChanged || versionChanged || loadingChanged || newIds != messageIds || selectionChanged
                || unreadBoundaryChanged
            else {
                synchronizeSelection(in: tableView)
                _ = handleExplicitNavigation(in: tableView)
                return
            }

            if selectionChanged, !chatChanged, !versionChanged, !unreadBoundaryChanged, newIds == messageIds {
                previousSelectedMessageId = parent.selectedMessageId
                synchronizeSelection(in: tableView)
                return
            }

            let oldRows = rows
            let oldFirstMessageId = messageIds.first
            let oldFirstRow = oldFirstMessageId.flatMap { id in oldRows.firstIndex { $0.messageId == id } }
            let oldFirstOffset = oldFirstRow.flatMap { row -> CGFloat? in
                tableView.rect(ofRow: row).minY - scrollView.contentView.bounds.minY
            }

            messageIds = newIds
            rows = computeRows(for: newIds)
            previousVersion = parent.model.messages.version
            previousIsLoadingMessages = parent.model.isLoadingMessages
            previousSelectedMessageId = parent.selectedMessageId
            previousUnreadBoundaryMessageId = parent.unreadBoundaryMessageId
            tableView.reloadData()
            synchronizeSelection(in: tableView)

            if handleExplicitNavigation(in: tableView) { return }

            if !hasPositionedInitialMessages, !parent.model.isLoadingMessages, !newIds.isEmpty {
                scrollToBottom(in: tableView, focus: false)
                hasPositionedInitialMessages = true
                parent.isAtBottom = true
            } else if let oldFirstMessageId,
                      let oldFirstOffset,
                      messageIds.first != oldFirstMessageId,
                      let newRow = rows.firstIndex(where: { $0.messageId == oldFirstMessageId })
            {
                restore(row: newRow, offset: oldFirstOffset, in: tableView)
            } else if parent.shouldFollowLatestMessage, oldRows.last?.messageId != rows.last?.messageId {
                scrollToBottom(in: tableView, focus: false)
            }
            updateVisibleState()
        }

        func startObservingScroll() {
            guard let scrollView else { return }
            scrollView.contentView.postsBoundsChangedNotifications = true
            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main,
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateVisibleState() }
            }
        }

        func stopObservingScroll() {
            if let scrollObserver {
                NotificationCenter.default.removeObserver(scrollObserver)
            }
            scrollObserver = nil
        }

        private func entry(at index: Int) -> Row? {
            rows.indices.contains(index) ? rows[index] : nil
        }

        /// Walks the chronological message ids once, inserting a day divider whenever the calendar
        /// day changes and the unread divider right before the first unread message - each as its
        /// own row, never bundled into a message's row.
        private func computeRows(for messageIds: [Int64]) -> [Row] {
            var result = [Row]()
            result.reserveCapacity(messageIds.count + 2)
            var previousMessage: Message?
            let groups = telegramVisualMessageAlbumGroups(
                orderedMessageIds: messageIds,
                messages: parent.model.messages.messages,
            )
            for group in groups {
                let id = group.representativeMessageId
                guard let message = parent.model.messages.messages[id] else { continue }
                let startsNewDay = previousMessage.map {
                    !Calendar.autoupdatingCurrent.isDate(
                        Date(timeIntervalSince1970: TimeInterval(message.date)),
                        inSameDayAs: Date(timeIntervalSince1970: TimeInterval($0.date)),
                    )
                } ?? true
                if startsNewDay {
                    result.append(.dayHeader(telegramMessageDayHeading(message.date)))
                }
                if let unreadBoundaryMessageId = parent.unreadBoundaryMessageId,
                   group.messageIds.contains(unreadBoundaryMessageId)
                {
                    result.append(.unreadHeader(parent.model.openedUnreadCount))
                }
                result.append(.message(id, albumMessageIds: group.isAlbum ? group.messageIds : nil))
                previousMessage = group.messageIds.last.flatMap { parent.model.messages.messages[$0] } ?? message
            }
            return result
        }

        private func rowView(for entry: Row, accessibilityBridge: MacMessageAccessibilityBridge) -> AnyView {
            switch entry {
            case .dayHeader(let title):
                AnyView(MacMessageDayHeader(title: title))
            case .unreadHeader(let count):
                AnyView(MacUnreadMessagesHeader(count: count))
            case .message(let id, let albumMessageIds):
                if let message = parent.model.messages.messages[id] {
                    AnyView(
                        MacMessageTableRow(
                            model: parent.model,
                            message: message,
                            albumMessages: albumMessageIds?.compactMap { parent.model.messages.messages[$0] } ?? [],
                            lastReadOutboxMessageId: parent.chat.lastReadOutboxMessageId,
                            showsSenderName: parent.chat.kind == .group,
                            isChannelMessage: parent.chat.kind == .channel,
                            accessibilityBridge: accessibilityBridge,
                        ),
                    )
                } else {
                    AnyView(EmptyView())
                }
            }
        }

        @discardableResult
        private func handleExplicitNavigation(in tableView: NSTableView) -> Bool {
            if let latestId = parent.model.latestHistoryTargetMessageId,
               parent.model.messages.messages[latestId] != nil
            {
                scrollToBottom(in: tableView, focus: true)
                parent.model.latestHistoryTargetMessageId = nil
                hasPositionedInitialMessages = true
                parent.isAtBottom = true
                return true
            }
            if let targetId = parent.model.navigationTargetMessageId,
               let row = rows.firstIndex(where: { $0.containsMessage(targetId) })
            {
                selectAndFocus(row: row, in: tableView, centered: true)
                parent.model.navigationTargetMessageId = nil
                hasPositionedInitialMessages = true
                return true
            }
            return false
        }

        private func synchronizeSelection(in tableView: NSTableView) {
            guard let selectedMessageId = parent.selectedMessageId,
                  let row = rows.firstIndex(where: { $0.messageId == selectedMessageId }),
                  tableView.selectedRow != row
            else { return }
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }

        private func selectAndFocus(row: Int, in tableView: NSTableView, centered: Bool) {
            guard rows.indices.contains(row) else { return }
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            if centered {
                let rowRect = tableView.rect(ofRow: row)
                let height = tableView.enclosingScrollView?.contentView.bounds.height ?? 0
                tableView.scroll(NSPoint(x: 0, y: max(0, rowRect.midY - height / 2)))
            } else {
                tableView.scrollRowToVisible(row)
            }
            tableView.window?.makeFirstResponder(tableView)
        }

        private func scrollToBottom(in tableView: NSTableView, focus: Bool) {
            guard !rows.isEmpty else { return }
            let row = rows.index(before: rows.endIndex)
            isRestoringScrollPosition = true
            DispatchQueue.main.async { [weak self, weak tableView] in
                guard let self, let tableView else { return }
                guard row < tableView.numberOfRows else {
                    self.isRestoringScrollPosition = false
                    return
                }
                tableView.scrollRowToVisible(row)
                if focus {
                    self.selectAndFocus(row: row, in: tableView, centered: false)
                } else if tableView.selectedRow < 0 {
                    tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                }
                self.isRestoringScrollPosition = false
                self.updateVisibleState()
            }
        }

        private func restore(row: Int, offset: CGFloat, in tableView: NSTableView) {
            isRestoringScrollPosition = true
            DispatchQueue.main.async { [weak self, weak tableView] in
                guard let self, let tableView else { return }
                tableView.scroll(NSPoint(x: 0, y: max(0, tableView.rect(ofRow: row).minY - offset)))
                self.isRestoringScrollPosition = false
                self.updateVisibleState()
            }
        }

        private func updateVisibleState() {
            guard !isRestoringScrollPosition,
                  hasPositionedInitialMessages,
                  let tableView,
                  !rows.isEmpty
            else { return }
            let visibleRows = tableView.rows(in: tableView.visibleRect)
            guard visibleRows.location != NSNotFound else { return }
            let lastVisibleRow = visibleRows.location + visibleRows.length - 1
            let atBottom = lastVisibleRow >= rows.count - 1
            if parent.isAtBottom != atBottom { parent.isAtBottom = atBottom }
            if visibleRows.location == 0,
               !parent.model.isLoadingMessages,
               !parent.model.isLoadingOlderMessages
            {
                parent.onLoadOlder()
            }
        }

    }
}

// MARK: - AppKit table views

/// Reactions and a link preview are exposed by overriding `accessibilityRows()` here, replacing
/// `NSTableView`'s own default per-row/per-cell exposure - three earlier attempts at overriding
/// `accessibilityChildren()` at other levels (SwiftUI's own grouping, `HostedMessageCell`,
/// `MessageTableRowView`) all failed identically. See `MacMessageTableRowAccessibilityElement` for
/// why the table itself, not a row or cell view, is the level this needed to happen at.
final class MessageNSTableView: NSTableView {
    override var acceptsFirstResponder: Bool { true }

    /// Bounded to `visibleRect`'s rows, not `0..<numberOfRows`: a long chat can have thousands of
    /// messages, and `rowView(atRow:makeIfNecessary:false)` already returns `nil` for anything not
    /// currently materialized, so scanning the full row count on every call - which VoiceOver does
    /// often enough for this to matter - was pure wasted work scaling with total history length
    /// rather than what's on screen, and was making VoiceOver noticeably sluggish.
    override func accessibilityRows() -> [NSAccessibilityRow]? {
        var accessibleRows: [NSAccessibilityRow] = []
        let visibleRange = rows(in: visibleRect)
        guard visibleRange.length > 0 else { return accessibleRows }
        for index in visibleRange.lowerBound..<visibleRange.upperBound {
            guard let rowView = self.rowView(atRow: index, makeIfNecessary: false),
                  let cell = rowView.view(atColumn: 0) as? NSView
            else { continue }
            let key = ObjectIdentifier(cell)
            let element = rowAccessibilityElements[key] ?? MacMessageTableRowAccessibilityElement(cell: cell, in: self)
            rowAccessibilityElements[key] = element
            let extras = (cell as? HostedMessageCell)?.accessibilityBridge.children ?? []
            element.update(index: index, extraDescriptors: extras, frame: rowView.accessibilityFrame())
            accessibleRows.append(element)
        }
        return accessibleRows
    }

    private var rowAccessibilityElements: [ObjectIdentifier: MacMessageTableRowAccessibilityElement] = [:]
}

private final class MessageTableRowView: NSTableRowView {}

private final class HostedMessageCell: NSTableCellView {
    let accessibilityBridge = MacMessageAccessibilityBridge()

    private var hostingView: NSHostingView<AnyView>?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        accessibilityBridge.owner = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setRootView(_ rootView: AnyView) {
        if let hostingView {
            hostingView.rootView = rootView
            return
        }
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        self.hostingView = hostingView
    }

    /// `false` for rows `accessibilityBridge.primary` never populates - day/unread headers - so
    /// those fall back to AppKit's normal discovery through `hostingView`, exactly as before. For
    /// message rows this makes the cell itself carry the message's label/value/actions directly
    /// (see `MacMessageAccessibilityBridge.primary`) rather than being an unlabeled pass-through: a
    /// `isAccessibilityElement(false)` cell that also reports real `accessibilityChildren()` reads
    /// as "empty cell" on a plain up/down-arrow focus instead of summarizing the message.
    override func isAccessibilityElement() -> Bool {
        accessibilityBridge.primary != nil
    }

    override func accessibilityLabel() -> String? {
        accessibilityBridge.primary?.label
    }

    override func accessibilityValue() -> Any? {
        let value = accessibilityBridge.primary?.value ?? ""
        return value.isEmpty ? nil : value
    }

    override func accessibilityPerformPress() -> Bool {
        guard let activate = accessibilityBridge.primary?.activate else { return false }
        MainActor.assumeIsolated {
            activate()
        }
        return true
    }

    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        guard let items = accessibilityBridge.primary?.customActions, !items.isEmpty else { return nil }
        return items.map { item in
            let action = MainActorClosureBox(run: item.action)
            return NSAccessibilityCustomAction(name: item.title) {
                MainActor.assumeIsolated {
                    action.run()
                }
                return true
            }
        }
    }

}

// MARK: - Hosted row content

private struct MacMessageTableRow: View {
    @Bindable var model: MacSessionModel
    let message: Message
    let albumMessages: [Message]
    let lastReadOutboxMessageId: Int64
    let showsSenderName: Bool
    let isChannelMessage: Bool
    let accessibilityBridge: MacMessageAccessibilityBridge

    var body: some View {
        MacMessageRow(
            model: model,
            message: message,
            albumMessages: albumMessages,
            lastReadOutboxMessageId: lastReadOutboxMessageId,
            showsSenderName: showsSenderName,
            isChannelMessage: isChannelMessage,
            accessibilityBridge: accessibilityBridge,
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity)
    }
}

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
                .accessibilityAddTraits(.isHeader)
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

private struct MacUnreadMessagesHeader: View {
    let count: Int
    var body: some View {
        HStack(spacing: 10) {
            Divider()
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)
                .accessibilityAddTraits(.isHeader)
            Divider()
        }
        .frame(height: 24)
    }
    private var title: String { "\(count) unread \(count == 1 ? "message" : "messages")" }
}
