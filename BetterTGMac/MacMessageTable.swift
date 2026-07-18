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
        tableView.accessibilityMenuHandler = context.coordinator.showMenuForSelectedRow
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
            case message(Int64)

            var messageId: Int64? {
                if case .message(let id) = self { id } else { nil }
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
            cell.setRootView(rowView(for: entry))
            return cell
        }

        func tableView(_: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            let rowView = MessageTableRowView()
            guard self.entry(at: row)?.messageId != nil else { return rowView }
            rowView.accessibilityMenuHandler = { [weak self, weak rowView] in
                guard let self, let rowView, let tableView = self.tableView else { return false }
                return self.showMenu(for: tableView.row(for: rowView))
            }
            return rowView
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

        func showMenuForSelectedRow() -> Bool {
            guard let tableView else { return false }
            return showMenu(for: tableView.selectedRow)
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
            for id in messageIds {
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
                if parent.unreadBoundaryMessageId == id {
                    result.append(.unreadHeader(parent.model.openedUnreadCount))
                }
                result.append(.message(id))
                previousMessage = message
            }
            return result
        }

        private func rowView(for entry: Row) -> AnyView {
            switch entry {
            case .dayHeader(let title):
                AnyView(MacMessageDayHeader(title: title))
            case .unreadHeader(let count):
                AnyView(MacUnreadMessagesHeader(count: count))
            case .message(let id):
                if let message = parent.model.messages.messages[id] {
                    AnyView(
                        MacMessageTableRow(
                            model: parent.model,
                            message: message,
                            lastReadOutboxMessageId: parent.chat.lastReadOutboxMessageId,
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
               let row = rows.firstIndex(where: { $0.messageId == targetId })
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

        private func showMenu(for row: Int) -> Bool {
            guard let tableView, self.entry(at: row)?.messageId != nil else { return false }
            if tableView.selectedRow != row {
                tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }
            guard let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: true) as? HostedMessageCell
            else { return false }
            return cell.showContextMenu()
        }
    }
}

// MARK: - AppKit table views

final class MessageNSTableView: NSTableView {
    var accessibilityMenuHandler: (() -> Bool)?

    override var acceptsFirstResponder: Bool { true }

    override func accessibilityPerformShowMenu() -> Bool {
        accessibilityMenuHandler?() ?? false
    }

}

private final class MessageTableRowView: NSTableRowView {
    var accessibilityMenuHandler: (() -> Bool)?

    override func accessibilityPerformShowMenu() -> Bool {
        accessibilityMenuHandler?() ?? false
    }
}

private final class HostedMessageCell: NSTableCellView {
    private var hostingView: NSHostingView<AnyView>?

    func setRootView(_ rootView: AnyView) {
        setAccessibilityElement(false)
        setAccessibilityLabel(nil)
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

    override func accessibilityPerformShowMenu() -> Bool {
        showContextMenu()
    }

    @discardableResult
    func showContextMenu() -> Bool {
        guard let hostingView, let window else { return false }
        let point = convert(NSPoint(x: bounds.midX, y: bounds.midY), to: nil)
        guard let event = NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: point,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1,
        ) else { return false }
        hostingView.rightMouseDown(with: event)
        return true
    }
}

// MARK: - Hosted row content

private struct MacMessageTableRow: View {
    @Bindable var model: MacSessionModel
    let message: Message
    let lastReadOutboxMessageId: Int64

    var body: some View {
        MacMessageRow(
            model: model,
            message: message,
            lastReadOutboxMessageId: lastReadOutboxMessageId,
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
            Spacer()
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isHeader)
    }
}

private struct MacUnreadMessagesHeader: View {
    let count: Int
    var body: some View {
        HStack(spacing: 10) {
            Divider()
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.tint)
            Divider()
        }
        .frame(height: 24)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isHeader)
    }
    private var title: String { "\(count) unread \(count == 1 ? "message" : "messages")" }
}
