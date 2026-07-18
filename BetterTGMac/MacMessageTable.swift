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
        var parent: MacMessageTable
        weak var tableView: MessageNSTableView?
        weak var scrollView: NSScrollView?

        private var messageIds = [Int64]()
        private var previousChatId: Int64?
        private var previousVersion: UInt64?
        private var previousIsLoadingMessages = false
        private var previousSelectedMessageId: Int64?
        private var hasPositionedInitialMessages = false
        private var scrollObserver: NSObjectProtocol?
        private var isRestoringScrollPosition = false

        init(parent: MacMessageTable) {
            self.parent = parent
        }

        func numberOfRows(in _: NSTableView) -> Int {
            messageIds.count
        }

        func tableView(_ tableView: NSTableView, viewFor _: NSTableColumn?, row: Int) -> NSView? {
            guard messageIds.indices.contains(row),
                  let message = parent.model.messages.messages[messageIds[row]]
            else { return nil }

            let identifier = NSUserInterfaceItemIdentifier("HostedMessage")
            let cell: HostedMessageCell
            if let reused = tableView.makeView(withIdentifier: identifier, owner: nil) as? HostedMessageCell {
                cell = reused
            } else {
                cell = HostedMessageCell()
                cell.identifier = identifier
            }
            cell.setRootView(rowView(for: message, at: row))
            return cell
        }

        func tableView(_: NSTableView, rowViewForRow _: Int) -> NSTableRowView? {
            let rowView = MessageTableRowView()
            rowView.accessibilityMenuHandler = { [weak self, weak rowView] in
                guard let self, let rowView, let tableView = self.tableView else { return false }
                return self.showMenu(for: tableView.row(for: rowView))
            }
            return rowView
        }

        func tableViewSelectionDidChange(_ notification: Foundation.Notification) {
            guard let tableView = notification.object as? NSTableView,
                  messageIds.indices.contains(tableView.selectedRow)
            else { return }
            parent.selectedMessageId = messageIds[tableView.selectedRow]
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

            if chatChanged {
                previousChatId = parent.chat.chatId
                previousVersion = nil
                previousIsLoadingMessages = parent.model.isLoadingMessages
                previousSelectedMessageId = nil
                hasPositionedInitialMessages = false
                messageIds = []
            }

            let selectionChanged = previousSelectedMessageId != parent.selectedMessageId
            guard chatChanged || versionChanged || loadingChanged || newIds != messageIds || selectionChanged else {
                synchronizeSelection(in: tableView)
                _ = handleExplicitNavigation(in: tableView)
                return
            }

            if selectionChanged, !chatChanged, !versionChanged, newIds == messageIds {
                previousSelectedMessageId = parent.selectedMessageId
                synchronizeSelection(in: tableView)
                return
            }

            let oldIds = messageIds
            let oldFirstId = oldIds.first
            let oldFirstOffset = oldFirstId.flatMap { id -> CGFloat? in
                guard let row = oldIds.firstIndex(of: id) else { return nil }
                return tableView.rect(ofRow: row).minY - scrollView.contentView.bounds.minY
            }

            messageIds = newIds
            previousVersion = parent.model.messages.version
            previousIsLoadingMessages = parent.model.isLoadingMessages
            previousSelectedMessageId = parent.selectedMessageId
            tableView.reloadData()
            synchronizeSelection(in: tableView)

            if handleExplicitNavigation(in: tableView) { return }

            if !hasPositionedInitialMessages, !parent.model.isLoadingMessages, !newIds.isEmpty {
                scrollToBottom(in: tableView, focus: false)
                hasPositionedInitialMessages = true
                parent.isAtBottom = true
            } else if let oldFirstId,
                      let oldFirstOffset,
                      oldIds.first != newIds.first,
                      let newRow = newIds.firstIndex(of: oldFirstId)
            {
                restore(row: newRow, offset: oldFirstOffset, in: tableView)
            } else if parent.shouldFollowLatestMessage, oldIds.last != newIds.last {
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

        private func rowView(for message: Message, at row: Int) -> AnyView {
            AnyView(
                MacMessageTableRow(
                    model: parent.model,
                    message: message,
                    lastReadOutboxMessageId: parent.chat.lastReadOutboxMessageId,
                    dayHeading: startsNewDay(at: row) ? telegramMessageDayHeading(message.date) : nil,
                    unreadCount: parent.unreadBoundaryMessageId == message.id ? parent.model.openedUnreadCount : nil,
                ),
            )
        }

        private func startsNewDay(at index: Int) -> Bool {
            guard messageIds.indices.contains(index),
                  let message = parent.model.messages.messages[messageIds[index]]
            else { return false }
            guard index > 0,
                  let previous = parent.model.messages.messages[messageIds[index - 1]]
            else { return true }
            return !Calendar.autoupdatingCurrent.isDate(
                Date(timeIntervalSince1970: TimeInterval(message.date)),
                inSameDayAs: Date(timeIntervalSince1970: TimeInterval(previous.date)),
            )
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
               let row = messageIds.firstIndex(of: targetId)
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
                  let row = messageIds.firstIndex(of: selectedMessageId),
                  tableView.selectedRow != row
            else { return }
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }

        private func selectAndFocus(row: Int, in tableView: NSTableView, centered: Bool) {
            guard messageIds.indices.contains(row) else { return }
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
            guard !messageIds.isEmpty else { return }
            let row = messageIds.index(before: messageIds.endIndex)
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
                  !messageIds.isEmpty
            else { return }
            let visibleRows = tableView.rows(in: tableView.visibleRect)
            guard visibleRows.location != NSNotFound else { return }
            let lastVisibleRow = visibleRows.location + visibleRows.length - 1
            let atBottom = lastVisibleRow >= messageIds.count - 1
            if parent.isAtBottom != atBottom { parent.isAtBottom = atBottom }
            if visibleRows.location == 0,
               !parent.model.isLoadingMessages,
               !parent.model.isLoadingOlderMessages
            {
                parent.onLoadOlder()
            }
        }

        private func showMenu(for row: Int) -> Bool {
            guard let tableView, messageIds.indices.contains(row) else { return false }
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
    let dayHeading: String?
    let unreadCount: Int?

    var body: some View {
        VStack(spacing: 0) {
            if let dayHeading { MacMessageDayHeader(title: dayHeading) }
            if let unreadCount { MacUnreadMessagesHeader(count: unreadCount) }
            MacMessageRow(
                model: model,
                message: message,
                lastReadOutboxMessageId: lastReadOutboxMessageId,
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
        }
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
