// ChatHistoryTableViewController.swift

import SwiftUI
import UIKit

// MARK: - ChatHistoryTableViewController

@MainActor final class ChatHistoryTableViewController: UIViewController, ChatHistoryNavigating {
    // MARK: Lifecycle

    init(navigator: ChatHistoryNavigator) {
        self.navigator = navigator
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Internal

    struct Configuration {
        let chatVM: ChatVM
        let messages: [CustomMessage]
        let unreadMessageId: Int64?
        let unreadCount: Int
        let currentUnreadCount: Int
        let unreadHeaderVoiceOverFocusRequest: Int
        let shouldShowProfileImage: Bool
        let isPreview: Bool
        let canLoadOlderMessages: Bool
        let canMarkMessagesRead: Bool
        let messageAccessibilityFocused: AccessibilityFocusState<Int64?>.Binding
        let dynamicTypeSize: DynamicTypeSize
        let bubbleCornerRadius: CGFloat
        let colorScheme: ColorScheme
        let layoutDirection: LayoutDirection
        let reduceMotion: Bool
        let onBackgroundTap: () -> Void
        let onScrollButtonFocused: () -> Void
    }

    override func loadView() {
        let containerView = UIView()
        containerView.backgroundColor = .clear

        tableView = ChatHistoryUITableView(frame: .zero, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 100
        tableView.alwaysBounceVertical = true
        tableView.showsVerticalScrollIndicator = false
        tableView.keyboardDismissMode = .interactive
        tableView.contentInsetAdjustmentBehavior = .never
        tableView.allowsSelection = false
        tableView.delegate = self
        tableView.onContentSizeChange = { [weak self] in
            self?.contentSizeDidChange()
        }
        tableView.register(ChatHistoryTableCell.self, forCellReuseIdentifier: ChatHistoryTableCell.reuseIdentifier)

        let backgroundTap = UITapGestureRecognizer(target: self, action: #selector(didTapTableView))
        backgroundTap.cancelsTouchesInView = false
        backgroundTap.require(toFail: tableView.panGestureRecognizer)
        tableView.addGestureRecognizer(backgroundTap)

        dataSource = UITableViewDiffableDataSource<Int, ChatHistoryItem.ID>(tableView: tableView) {
            [weak self] tableView, indexPath, id in
            guard let self,
                  let configuration,
                  let item = itemsById[id],
                  let cell = tableView.dequeueReusableCell(
                      withIdentifier: ChatHistoryTableCell.reuseIdentifier,
                      for: indexPath,
                  ) as? ChatHistoryTableCell
            else { return UITableViewCell() }
            cell.configure(rootView: rootView(for: item, configuration: configuration))
            return cell
        }

        scrollToBottomButton.translatesAutoresizingMaskIntoConstraints = false
        scrollToBottomButton.addTarget(self, action: #selector(didTapScrollToBottom), for: .touchUpInside)
        scrollToBottomButton.onAccessibilityFocus = { [weak self] in
            self?.configuration?.onScrollButtonFocused()
        }

        containerView.addSubview(tableView)
        containerView.addSubview(scrollToBottomButton)
        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: containerView.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            scrollToBottomButton.widthAnchor.constraint(equalToConstant: 48),
            scrollToBottomButton.heightAnchor.constraint(equalToConstant: 48),
            scrollToBottomButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8),
            scrollToBottomButton.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -8),
        ])

        view = containerView
        navigator.attach(self)

        #if DEBUG
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(debugLogVisibleRowHeights(_:)),
            name: UIAccessibility.elementFocusedNotification,
            object: nil,
        )
        #endif
    }

    #if DEBUG
    /// Companion to `ChatScrollDiagnostics`'s own focus-notification listener: logs the real,
    /// measured height of every currently-visible row alongside each VoiceOver focus change.
    @objc private func debugLogVisibleRowHeights(_: Notification) {
        guard let indexPaths = tableView.indexPathsForVisibleRows, !indexPaths.isEmpty else { return }
        let heights = indexPaths.compactMap { indexPath -> String? in
            guard let id = dataSource.itemIdentifier(for: indexPath) else { return nil }
            let height = tableView.rectForRow(at: indexPath).height
            return "\(id): \(Int(height))pt"
        }
        chatScrollTrace(
            "viewport=\(Int(tableView.bounds.height))pt offset=\(Int(tableView.contentOffset.y)) " +
                "visible row heights: \(heights.joined(separator: ", "))",
        )
    }
    #endif

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let newSize = tableView.bounds.size
        guard newSize != lastBoundsSize else { return }
        let visibleAnchor = captureVisibleAnchor()
        let shouldKeepBottom = lastBoundsSize != .zero && lastIsAtBottom && allowsAutomaticBottomScroll
        let widthChanged = lastBoundsSize != .zero && abs(newSize.width - lastBoundsSize.width) > 0.5
        chatScrollTrace(
            "viewDidLayoutSubviews \(lastBoundsSize) -> \(newSize) " +
                "shouldKeepBottom=\(shouldKeepBottom) widthChanged=\(widthChanged)",
        )
        lastBoundsSize = newSize
        viewport.height = newSize.height
        tableView.layoutIfNeeded()
        updateTopContentInset()
        tableView.layoutIfNeeded()
        if shouldKeepBottom {
            _ = scrollToBottom(animated: false)
        } else if widthChanged {
            restoreVisibleAnchor(visibleAnchor)
        }
        navigator.flushPendingRequest()
        updateScrollState()
    }

    func update(_ configuration: Configuration) {
        loadViewIfNeeded()
        updateGeneration += 1
        let generation = updateGeneration
        let oldConfiguration = self.configuration
        let oldItems = items
        let oldItemsById = itemsById
        let canMarkMessagesReadBecameEnabled = oldConfiguration?.canMarkMessagesRead != true
            && configuration.canMarkMessagesRead
        let canLoadOlderMessagesBecameEnabled = oldConfiguration?.canLoadOlderMessages != true
            && configuration.canLoadOlderMessages
        let wasAtBottom = !items.isEmpty && lastIsAtBottom
        let visibleAnchor = captureVisibleAnchor()
        let newItems = ChatHistoryItem.makeItems(
            messages: configuration.messages,
            unreadMessageId: configuration.unreadMessageId,
            unreadCount: configuration.unreadCount,
            unreadHeaderVoiceOverFocusRequest: configuration.unreadHeaderVoiceOverFocusRequest,
        )
        let environmentChanged = oldConfiguration.map(environmentSignature) != environmentSignature(configuration)
        let contentChanged = oldItemsById.count != newItems.count
            || zip(oldItems, newItems).contains { oldItem, newItem in
                oldItem.id != newItem.id || oldItem.contentSignature != newItem.contentSignature
            }

        self.configuration = configuration
        scrollToBottomButton.update(unreadCount: configuration.currentUnreadCount)
        scrollToBottomButton.setVisible(
            configuration.chatVM.showScrollToBottomButton,
            animated: oldConfiguration != nil && !configuration.reduceMotion,
        )
        items = newItems
        itemsById = Dictionary(uniqueKeysWithValues: newItems.map { ($0.id, $0) })

        guard contentChanged || environmentChanged else {
            navigator.flushPendingRequest()
            if canLoadOlderMessagesBecameEnabled {
                lastIsNearTop = false
                updateScrollState()
            }
            if canMarkMessagesReadBecameEnabled {
                reportVisibleMessages()
            }
            return
        }

        var snapshot = NSDiffableDataSourceSnapshot<Int, ChatHistoryItem.ID>()
        snapshot.appendSections([0])
        snapshot.appendItems(newItems.map(\.id))

        let existingIds = Set(dataSource.snapshot().itemIdentifiers)
        let newIds = Set(newItems.map(\.id))
        var changedIds = Set(newIds.intersection(existingIds).filter { id in
            oldItemsById[id]?.contentSignature != itemsById[id]?.contentSignature
        })
        if environmentChanged {
            changedIds = newIds.intersection(existingIds)
        }
        let validChangedIds = Array(changedIds.filter { existingIds.contains($0) && newIds.contains($0) })
        if !validChangedIds.isEmpty {
            snapshot.reconfigureItems(validChangedIds)
        }

        chatScrollTrace(
            "update: \(oldItems.count) -> \(newItems.count) items, wasAtBottom=\(wasAtBottom) " +
                "environmentChanged=\(environmentChanged)",
        )
        dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
            guard let self, generation == updateGeneration else { return }
            tableView.layoutIfNeeded()
            updateTopContentInset()
            tableView.layoutIfNeeded()
            if wasAtBottom && allowsAutomaticBottomScroll {
                chatScrollTrace("update completion: scrollToBottom (wasAtBottom)")
                _ = scrollToBottom(animated: false)
            } else if environmentChanged
                || itemsBeforeAnchorChanged(visibleAnchor, oldItems: oldItems, newItems: newItems)
            {
                chatScrollTrace("update completion: restoreVisibleAnchor")
                restoreVisibleAnchor(visibleAnchor)
            }
            navigator.flushPendingRequest()
            if canLoadOlderMessagesBecameEnabled {
                lastIsNearTop = false
            }
            updateScrollState()
            if canMarkMessagesReadBecameEnabled {
                reportVisibleMessages()
            }
        }
    }

    func perform(_ request: ChatHistoryNavigator.Request) -> Bool {
        loadViewIfNeeded()
        tableView.layoutIfNeeded()
        switch request {
        case .bottom(let animated):
            return scrollToBottom(animated: animated && configuration?.reduceMotion != true)
        case .message(let messageId, let anchor, let animated):
            return scroll(
                to: .message(messageId),
                anchor: anchor,
                animated: animated && configuration?.reduceMotion != true,
            )
        case .unread(let messageId):
            return scroll(to: .unread(messageId), anchor: .top, animated: false)
        }
    }

    func navigatorDidDismantle() {
        navigator.detach(self)
    }

    // MARK: Private

    private struct EnvironmentSignature: Equatable {
        let dynamicTypeSize: DynamicTypeSize
        let bubbleCornerRadius: CGFloat
        let colorScheme: ColorScheme
        let layoutDirection: LayoutDirection
        let shouldShowProfileImage: Bool
        let isPreview: Bool
    }

    private struct VisibleAnchor {
        let id: ChatHistoryItem.ID
        let offsetFromViewportTop: CGFloat
    }

    private let navigator: ChatHistoryNavigator
    private let viewport = ChatHistoryViewport()
    private let scrollToBottomButton = ChatScrollToBottomButton(type: .custom)
    // Not `private`: exposed at internal (module) visibility so `@testable import` tests can read
    // the real scroll geometry (`tableView.contentOffset`, `dataSource.indexPath(for:)`) instead of
    // inferring it indirectly. No behavior change - still invisible outside this module.
    var tableView: ChatHistoryUITableView!
    var dataSource: UITableViewDiffableDataSource<Int, ChatHistoryItem.ID>!
    private var configuration: Configuration?
    private var items = [ChatHistoryItem]()
    private var itemsById = [ChatHistoryItem.ID: ChatHistoryItem]()
    private var lastBoundsSize = CGSize.zero
    private var lastIsAtBottom = true
    private var lastIsNearTop = false
    private var updateGeneration = 0
    private var programmaticScrollInProgress = false

    private var minimumContentOffsetY: CGFloat {
        -tableView.adjustedContentInset.top
    }

    private var maximumContentOffsetY: CGFloat {
        max(
            minimumContentOffsetY,
            tableView.contentSize.height - tableView.bounds.height + tableView.adjustedContentInset.bottom,
        )
    }

    private func rootView(for item: ChatHistoryItem, configuration: Configuration) -> some View {
        ChatHistoryRowView(
            item: item,
            shouldShowProfileImage: configuration.shouldShowProfileImage,
            messageAccessibilityFocused: configuration.messageAccessibilityFocused,
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 2.5)
        .environment(configuration.chatVM)
        .environment(viewport)
        .environment(\.isPreview, configuration.isPreview)
        .environment(\.telegramBubbleCornerRadius, configuration.bubbleCornerRadius)
        .environment(\.colorScheme, configuration.colorScheme)
        .environment(\.layoutDirection, configuration.layoutDirection)
        .dynamicTypeSize(configuration.dynamicTypeSize)
        .tint(Color(uiColor: tableView.tintColor))
    }

    private func environmentSignature(_ configuration: Configuration) -> EnvironmentSignature {
        EnvironmentSignature(
            dynamicTypeSize: configuration.dynamicTypeSize,
            bubbleCornerRadius: configuration.bubbleCornerRadius,
            colorScheme: configuration.colorScheme,
            layoutDirection: configuration.layoutDirection,
            shouldShowProfileImage: configuration.shouldShowProfileImage,
            isPreview: configuration.isPreview,
        )
    }

    private func captureVisibleAnchor() -> VisibleAnchor? {
        guard let indexPath = tableView.indexPathsForVisibleRows?.min(),
              let id = dataSource.itemIdentifier(for: indexPath)
        else { return nil }
        let rowFrame = tableView.rectForRow(at: indexPath)
        return VisibleAnchor(id: id, offsetFromViewportTop: rowFrame.minY - tableView.contentOffset.y)
    }

    private func restoreVisibleAnchor(_ anchor: VisibleAnchor?) {
        guard let anchor,
              let indexPath = dataSource.indexPath(for: anchor.id)
        else { return }
        tableView.layoutIfNeeded()
        let targetY = tableView.rectForRow(at: indexPath).minY - anchor.offsetFromViewportTop
        let clampedY = min(maximumContentOffsetY, max(minimumContentOffsetY, targetY))
        chatScrollTrace("restoreVisibleAnchor \(anchor.id) offset \(tableView.contentOffset.y) -> \(clampedY)")
        tableView.setContentOffset(CGPoint(x: tableView.contentOffset.x, y: clampedY), animated: false)
    }

    private func itemsBeforeAnchorChanged(
        _ anchor: VisibleAnchor?,
        oldItems: [ChatHistoryItem],
        newItems: [ChatHistoryItem],
    ) -> Bool {
        guard let anchor else { return false }
        if ChatHistoryTableMetrics.itemsBeforeAnchorChanged(
            anchor.id,
            oldIDs: oldItems.map(\.id),
            newIDs: newItems.map(\.id),
        ) {
            return true
        }
        guard let oldIndex = oldItems.firstIndex(where: { $0.id == anchor.id }),
              let newIndex = newItems.firstIndex(where: { $0.id == anchor.id })
        else { return false }

        return zip(oldItems[..<oldIndex], newItems[..<newIndex]).contains { oldItem, newItem in
            oldItem.contentSignature != newItem.contentSignature
        }
    }

    private func updateTopContentInset() {
        let desiredTopInset = ChatHistoryTableMetrics.topContentInset(
            contentHeight: tableView.contentSize.height,
            viewportHeight: tableView.bounds.height,
        )
        guard abs(tableView.contentInset.top - desiredTopInset) > 0.5 else { return }
        tableView.contentInset.top = desiredTopInset
    }

    private func contentSizeDidChange() {
        let shouldKeepBottom = lastIsAtBottom && allowsAutomaticBottomScroll
            && !tableView.isDragging && !tableView.isDecelerating
        chatScrollTrace("contentSizeDidChange -> \(tableView.contentSize) shouldKeepBottom=\(shouldKeepBottom)")
        updateTopContentInset()
        tableView.layoutIfNeeded()
        if shouldKeepBottom {
            _ = scrollToBottom(animated: false)
        } else {
            updateScrollState()
        }
    }

    /// VoiceOver navigation need not set the scroll view's dragging/decelerating flags. Let it
    /// own scrolling during reading; explicit initial positioning and navigation still work.
    private var allowsAutomaticBottomScroll: Bool {
        !UIAccessibility.isVoiceOverRunning
    }

    private func scrollToBottom(animated: Bool) -> Bool {
        guard let id = items.last?.id,
              let indexPath = dataSource.indexPath(for: id)
        else { return false }
        guard abs(maximumContentOffsetY - tableView.contentOffset.y) > 0.5 else {
            programmaticScrollInProgress = false
            updateScrollState()
            return true
        }
        chatScrollTrace("scrollToBottom(animated: \(animated)) offset \(tableView.contentOffset.y) -> \(maximumContentOffsetY)")
        programmaticScrollInProgress = true
        tableView.scrollToRow(at: indexPath, at: .bottom, animated: animated)
        if !animated {
            programmaticScrollInProgress = false
            updateScrollState()
        }
        return true
    }

    private func scroll(to id: ChatHistoryItem.ID, anchor: ChatHistoryNavigator.Anchor, animated: Bool) -> Bool {
        guard let indexPath = dataSource.indexPath(for: id) else { return false }
        let position: UITableView.ScrollPosition =
            switch anchor {
            case .top: .top
            case .center: .middle
            case .bottom: .bottom
            }
        programmaticScrollInProgress = true
        tableView.scrollToRow(at: indexPath, at: position, animated: animated)
        if !animated {
            programmaticScrollInProgress = false
            updateScrollState()
        }
        return true
    }

    private func reportVisibleMessages() {
        tableView.indexPathsForVisibleRows?.forEach(reportMessage(at:))
    }

    private func reportMessage(at indexPath: IndexPath) {
        guard configuration?.isPreview == false,
              configuration?.canMarkMessagesRead == true,
              let id = dataSource.itemIdentifier(for: indexPath),
              let messageId = itemsById[id]?.messageId
        else { return }
        configuration?.chatVM.viewMessage(id: messageId)
    }

    @objc private func didTapTableView() {
        configuration?.onBackgroundTap()
    }

    @objc private func didTapScrollToBottom() {
        navigator.scrollToBottom(animated: true)
    }

    private func updateScrollState() {
        let state = ChatHistoryTableMetrics.scrollState(
            contentHeight: tableView.contentSize.height,
            viewportHeight: tableView.bounds.height,
            topInset: tableView.adjustedContentInset.top,
            bottomInset: tableView.adjustedContentInset.bottom,
            contentOffsetY: tableView.contentOffset.y,
        )
        scrollToBottomButton.setVisible(
            state.shouldShowBottomButton,
            animated: configuration?.reduceMotion != true,
        )
        if state.isAtBottom != lastIsAtBottom
            || state.shouldShowBottomButton != configuration?.chatVM.showScrollToBottomButton
        {
            chatScrollTrace(
                "updateScrollState: isAtBottom \(lastIsAtBottom) -> \(state.isAtBottom), " +
                    "showButton -> \(state.shouldShowBottomButton), offset=\(tableView.contentOffset.y) " +
                    "programmaticScroll=\(programmaticScrollInProgress)",
            )
            lastIsAtBottom = state.isAtBottom
            configuration?.chatVM.updateBottomVisibility(
                isLastMessageVisible: state.isAtBottom,
                shouldShowButton: state.shouldShowBottomButton,
            )
        }

        let isNearTop = tableView.contentSize.height > tableView.bounds.height
            && tableView.contentOffset.y <= minimumContentOffsetY + 250
        if !lastIsNearTop,
           isNearTop,
           !programmaticScrollInProgress,
           configuration?.canLoadOlderMessages == true,
           configuration?.isPreview == false
        {
            chatScrollTrace("updateScrollState: triggering loadMessages (isNearTop)")
            configuration?.chatVM.loadMessages()
        }
        lastIsNearTop = isNearTop
    }
}

// MARK: UITableViewDelegate

extension ChatHistoryTableViewController: UITableViewDelegate {
    func scrollViewWillBeginDragging(_: UIScrollView) {
        programmaticScrollInProgress = false
    }

    func scrollViewDidScroll(_: UIScrollView) {
        updateScrollState()
    }

    func scrollViewDidEndScrollingAnimation(_: UIScrollView) {
        programmaticScrollInProgress = false
        updateScrollState()
    }

    func scrollViewDidEndDecelerating(_: UIScrollView) {
        updateScrollState()
    }

    func tableView(_: UITableView, willDisplay _: UITableViewCell, forRowAt indexPath: IndexPath) {
        reportMessage(at: indexPath)
    }
}
