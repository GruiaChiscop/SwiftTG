// ChatHistoryCollectionViewController.swift

import SwiftUI
import UIKit

// MARK: - ChatHistoryCollectionViewController

@MainActor final class ChatHistoryCollectionViewController: UIViewController, ChatHistoryNavigating {
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
        let focusedMessageId: Int64?
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

        collectionView = ChatHistoryUICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.showsVerticalScrollIndicator = false
        collectionView.keyboardDismissMode = .interactive
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.delegate = self
        collectionView.register(
            ChatHistoryHostingCell.self,
            forCellWithReuseIdentifier: ChatHistoryHostingCell.reuseIdentifier,
        )
        let backgroundTap = UITapGestureRecognizer(target: self, action: #selector(didTapCollectionView))
        backgroundTap.cancelsTouchesInView = false
        backgroundTap.require(toFail: collectionView.panGestureRecognizer)
        collectionView.addGestureRecognizer(backgroundTap)
        layout.heightProvider = { [weak self] index, width in
            self?.heightForItem(at: index, width: width) ?? 1
        }
        dataSource = UICollectionViewDiffableDataSource<Int, ChatHistoryItem.ID>(
            collectionView: collectionView,
        ) { [weak self] collectionView, indexPath, id in
            guard let self,
                  let item = itemsById[id],
                  let cell = collectionView.dequeueReusableCell(
                      withReuseIdentifier: ChatHistoryHostingCell.reuseIdentifier,
                      for: indexPath,
                  ) as? ChatHistoryHostingCell
            else { return UICollectionViewCell() }
            cell.configure(rootView: rootView(for: item, reportsHeight: true))
            return cell
        }

        scrollToBottomButton.translatesAutoresizingMaskIntoConstraints = false
        scrollToBottomButton.addTarget(self, action: #selector(didTapScrollToBottom), for: .touchUpInside)
        scrollToBottomButton.onAccessibilityFocus = { [weak self] in
            self?.configuration?.onScrollButtonFocused()
        }

        containerView.addSubview(collectionView)
        containerView.addSubview(scrollToBottomButton)
        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: containerView.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            scrollToBottomButton.widthAnchor.constraint(equalToConstant: 48),
            scrollToBottomButton.heightAnchor.constraint(equalToConstant: 48),
            scrollToBottomButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8),
            scrollToBottomButton.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -8),
        ])

        view = containerView
        navigator.attach(self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let newSize = collectionView.bounds.size
        guard newSize != lastBoundsSize else { return }
        let anchor = captureVisibleAnchor()
        let shouldKeepBottom = lastBoundsSize != .zero && lastIsAtBottom
        let widthChanged = abs(newSize.width - lastBoundsSize.width) > 0.5
        lastBoundsSize = newSize
        if widthChanged {
            heightCache.removeAll(keepingCapacity: true)
        }
        invalidateLayoutPreservingPosition(
            anchor: anchor,
            shouldKeepBottom: shouldKeepBottom,
            itemCount: items.count,
        )
        collectionView.layoutIfNeeded()
        updateScrollState()
    }

    func update(_ configuration: Configuration) {
        loadViewIfNeeded()
        updateGeneration += 1
        let generation = updateGeneration
        let oldConfiguration = self.configuration
        let canMarkMessagesReadBecameEnabled = oldConfiguration?.canMarkMessagesRead != true
            && configuration.canMarkMessagesRead
        let oldItemsById = itemsById
        let anchor = captureVisibleAnchor()
        let shouldKeepBottom = !items.isEmpty && lastIsAtBottom
        let newItems = ChatHistoryItem.makeItems(
            messages: configuration.messages,
            unreadMessageId: configuration.unreadMessageId,
            unreadCount: configuration.unreadCount,
            unreadHeaderVoiceOverFocusRequest: configuration.unreadHeaderVoiceOverFocusRequest,
        )
        let environmentChanged = oldConfiguration.map(environmentSignature) != environmentSignature(configuration)
        let contentChanged = oldItemsById.count != newItems.count
            || zip(items, newItems).contains { oldItem, newItem in
                oldItem.id != newItem.id || oldItem.contentSignature != newItem.contentSignature
            }
        let focusedMessageChanged = oldConfiguration?.focusedMessageId != configuration.focusedMessageId
        if environmentChanged {
            heightCache.removeAll(keepingCapacity: true)
        }

        self.configuration = configuration
        scrollToBottomButton.update(unreadCount: configuration.currentUnreadCount)
        scrollToBottomButton.setVisible(
            configuration.chatVM.showScrollToBottomButton,
            animated: oldConfiguration != nil && !configuration.reduceMotion,
        )
        items = newItems
        itemsById = Dictionary(uniqueKeysWithValues: newItems.map { ($0.id, $0) })

        // SwiftUI updates this representable for unrelated state as well (for example when the
        // scroll-to-bottom button appears or receives VoiceOver focus). Reapplying an identical
        // diffable snapshot during those updates interrupts an active pan and can make UIKit move
        // accessibility focus to a newly configured cell.
        guard contentChanged || environmentChanged || focusedMessageChanged else {
            navigator.flushPendingRequest()
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
        } else if focusedMessageChanged {
            if let oldFocused = oldConfiguration?.focusedMessageId {
                changedIds.insert(.message(oldFocused))
            }
            if let newFocused = configuration.focusedMessageId {
                changedIds.insert(.message(newFocused))
            }
        }
        let validChangedIds = Array(changedIds.filter { newIds.contains($0) && existingIds.contains($0) })
        if !validChangedIds.isEmpty {
            snapshot.reconfigureItems(validChangedIds)
        }

        dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
            guard let self, generation == updateGeneration else { return }
            collectionView.layoutIfNeeded()
            navigator.flushPendingRequest()
            updateScrollState()
            if canMarkMessagesReadBecameEnabled {
                reportVisibleMessages()
            }
        }
        invalidateLayoutPreservingPosition(
            anchor: anchor,
            shouldKeepBottom: shouldKeepBottom,
            itemCount: newItems.count,
        )
    }

    func perform(_ request: ChatHistoryNavigator.Request) -> Bool {
        loadViewIfNeeded()
        collectionView.layoutIfNeeded()
        switch request {
        case .bottom(let animated):
            guard !items.isEmpty else { return false }
            setBottomOffset(animated: animated && configuration?.reduceMotion != true)
            return true
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

    private struct HeightCacheEntry {
        let signature: ChatHistoryItem.ContentSignature
        let environment: EnvironmentSignature
        let width: CGFloat
        let height: CGFloat
    }

    private struct VisibleAnchor {
        let id: ChatHistoryItem.ID
        let offsetFromViewportTop: CGFloat
    }

    private let navigator: ChatHistoryNavigator
    private let layout = ChatHistoryCollectionLayout()
    private let measuringController = UIHostingController(rootView: AnyView(EmptyView()))
    private let scrollToBottomButton = ChatScrollToBottomButton(type: .custom)

    private var collectionView: ChatHistoryUICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, ChatHistoryItem.ID>!
    private var configuration: Configuration?
    private var items = [ChatHistoryItem]()
    private var itemsById = [ChatHistoryItem.ID: ChatHistoryItem]()
    private var heightCache = [ChatHistoryItem.ID: HeightCacheEntry]()
    private var lastBoundsSize = CGSize.zero
    private var lastIsAtBottom = true
    private var lastIsNearTop = false
    private var updateGeneration = 0
    private var programmaticScrollInProgress = false

    private var minimumContentOffsetY: CGFloat {
        -collectionView.adjustedContentInset.top
    }

    private var maximumContentOffsetY: CGFloat {
        max(
            minimumContentOffsetY,
            collectionView.contentSize.height - collectionView.bounds.height + collectionView.adjustedContentInset
                .bottom,
        )
    }

    private func rootView(for item: ChatHistoryItem, reportsHeight: Bool) -> AnyView {
        guard let configuration else { return AnyView(EmptyView()) }
        let row = ChatHistoryRowView(
            item: item,
            shouldShowProfileImage: configuration.shouldShowProfileImage,
            messageAccessibilityFocused: configuration.messageAccessibilityFocused,
        )
        let measuredRow = ChatHistoryMeasuredRow(
            row: row,
            reportHeight: reportsHeight
                ? { [weak self] height in
                    self?.report(height: height, for: item.id)
                }
                : nil,
        )
        return AnyView(
            measuredRow
                .environment(configuration.chatVM)
                .environment(\.isPreview, configuration.isPreview)
                .environment(\.telegramBubbleCornerRadius, configuration.bubbleCornerRadius)
                .environment(\.colorScheme, configuration.colorScheme)
                .environment(\.layoutDirection, configuration.layoutDirection)
                .dynamicTypeSize(configuration.dynamicTypeSize)
                .tint(Color(uiColor: collectionView.tintColor)),
        )
    }

    private func reportVisibleMessages() {
        collectionView.indexPathsForVisibleItems.forEach(reportMessage(at:))
    }

    private func reportMessage(at indexPath: IndexPath) {
        guard configuration?.isPreview == false,
              configuration?.canMarkMessagesRead == true,
              items.indices.contains(indexPath.item),
              let messageId = items[indexPath.item].messageId
        else { return }
        configuration?.chatVM.viewMessage(id: messageId)
    }

    @objc private func didTapCollectionView() {
        configuration?.onBackgroundTap()
    }

    @objc private func didTapScrollToBottom() {
        navigator.scrollToBottom(animated: true)
    }

    private func heightForItem(at index: Int, width: CGFloat) -> CGFloat {
        guard items.indices.contains(index), let configuration else { return 1 }
        let item = items[index]
        let environment = environmentSignature(configuration)
        if let cached = heightCache[item.id],
           cached.signature == item.contentSignature,
           cached.environment == environment,
           abs(cached.width - width) < 0.5
        {
            return cached.height
        }

        measuringController.rootView = rootView(for: item, reportsHeight: false)
        measuringController.view.backgroundColor = .clear
        let measured = measuringController.sizeThatFits(
            in: CGSize(width: width, height: 50000),
        )
        let height = max(1, ceil(measured.height))
        heightCache[item.id] = HeightCacheEntry(
            signature: item.contentSignature,
            environment: environment,
            width: width,
            height: height,
        )
        return height
    }

    private func report(height: CGFloat, for id: ChatHistoryItem.ID) {
        guard let item = itemsById[id], let configuration else { return }
        let width = collectionView.bounds.width
        let currentHeight = heightCache[id]?.height
        guard currentHeight == nil || abs((currentHeight ?? 0) - height) > 0.5 else { return }
        let signature = item.contentSignature
        let environment = environmentSignature(configuration)
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self,
                  itemsById[id]?.contentSignature == signature,
                  abs(collectionView.bounds.width - width) < 0.5
            else { return }
            applyReportedHeight(height, for: id, signature: signature, environment: environment, width: width)
        }
    }

    private func applyReportedHeight(
        _ height: CGFloat,
        for id: ChatHistoryItem.ID,
        signature: ChatHistoryItem.ContentSignature,
        environment: EnvironmentSignature,
        width: CGFloat,
    ) {
        guard let currentItem = itemsById[id], currentItem.contentSignature == signature else { return }
        let anchor = captureVisibleAnchor()
        let shouldKeepBottom = lastIsAtBottom
        heightCache[id] = HeightCacheEntry(
            signature: signature,
            environment: environment,
            width: width,
            height: max(1, ceil(height)),
        )
        UIView.performWithoutAnimation {
            invalidateLayoutPreservingPosition(
                anchor: anchor,
                shouldKeepBottom: shouldKeepBottom,
                itemCount: items.count,
            )
            collectionView.layoutIfNeeded()
        }
        updateScrollState()
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
        guard !items.isEmpty else { return nil }
        let viewport = CGRect(origin: collectionView.contentOffset, size: collectionView.bounds.size)
        guard let first = layout.layoutAttributesForElements(in: viewport)?
            .filter({ $0.frame.maxY > viewport.minY })
            .min(by: { $0.frame.minY < $1.frame.minY }),
            items.indices.contains(first.indexPath.item)
        else { return nil }
        return VisibleAnchor(
            id: items[first.indexPath.item].id,
            offsetFromViewportTop: first.frame.minY - collectionView.contentOffset.y,
        )
    }

    private func invalidateLayoutPreservingPosition(
        anchor: VisibleAnchor?,
        shouldKeepBottom: Bool,
        itemCount: Int,
    ) {
        let projectedContentSize = layout.projectedContentSize(itemCount: itemCount)
        let projectedMaximumY = max(
            minimumContentOffsetY,
            projectedContentSize.height
                - collectionView.bounds.height
                + collectionView.adjustedContentInset.bottom,
        )

        let targetY: CGFloat? =
            if shouldKeepBottom {
                projectedMaximumY
            } else if let anchor,
                      let newIndex = items.firstIndex(where: { $0.id == anchor.id }),
                      let projectedFrame = layout.projectedFrame(at: newIndex, itemCount: itemCount)
            {
                projectedFrame.minY - anchor.offsetFromViewportTop
            } else {
                nil
            }

        let adjustment: CGPoint
        if let targetY {
            let clampedY = min(projectedMaximumY, max(minimumContentOffsetY, targetY))
            adjustment = CGPoint(x: 0, y: clampedY - collectionView.contentOffset.y)
        } else {
            adjustment = .zero
        }
        layout.invalidateLayout(contentOffsetAdjustment: adjustment)
    }

    private func scroll(to id: ChatHistoryItem.ID, anchor: ChatHistoryNavigator.Anchor, animated: Bool) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }),
              let attributes = layout.layoutAttributesForItem(at: IndexPath(item: index, section: 0))
        else { return false }
        let targetY =
            switch anchor {
            case .top:
                attributes.frame.minY
            case .center:
                attributes.frame.midY - collectionView.bounds.height / 2
            case .bottom:
                attributes.frame.maxY - collectionView.bounds.height
            }
        setVerticalOffset(targetY, animated: animated)
        return true
    }

    private func setBottomOffset(animated: Bool) {
        setVerticalOffset(maximumContentOffsetY, animated: animated)
    }

    private func setVerticalOffset(_ y: CGFloat, animated: Bool) {
        let clampedY = min(maximumContentOffsetY, max(minimumContentOffsetY, y))
        guard abs(clampedY - collectionView.contentOffset.y) > 0.5 else {
            programmaticScrollInProgress = false
            updateScrollState()
            return
        }
        programmaticScrollInProgress = true
        collectionView.setContentOffset(CGPoint(x: collectionView.contentOffset.x, y: clampedY), animated: animated)
        if !animated {
            programmaticScrollInProgress = false
            updateScrollState()
        }
    }

    private func updateScrollState() {
        let distanceFromBottom = maximumContentOffsetY - collectionView.contentOffset.y
        let isAtBottom = distanceFromBottom < 20
        let pageHeight = max(
            1,
            collectionView.bounds.height
                - collectionView.adjustedContentInset.top
                - collectionView.adjustedContentInset.bottom,
        )
        let shouldShowBottomButton = distanceFromBottom > pageHeight
        scrollToBottomButton.setVisible(
            shouldShowBottomButton,
            animated: configuration?.reduceMotion != true,
        )
        if isAtBottom != lastIsAtBottom
            || shouldShowBottomButton != configuration?.chatVM.showScrollToBottomButton
        {
            lastIsAtBottom = isAtBottom
            configuration?.chatVM.updateBottomVisibility(
                isLastMessageVisible: isAtBottom,
                shouldShowButton: shouldShowBottomButton,
            )
        }

        let isNearTop = collectionView.contentSize.height > collectionView.bounds.height
            && collectionView.contentOffset.y <= minimumContentOffsetY + 250
        if !lastIsNearTop,
           isNearTop,
           !programmaticScrollInProgress,
           configuration?.canLoadOlderMessages == true,
           configuration?.isPreview == false
        {
            configuration?.chatVM.loadMessages()
        }
        lastIsNearTop = isNearTop
    }
}

// MARK: UICollectionViewDelegate

extension ChatHistoryCollectionViewController: UICollectionViewDelegate {
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

    func collectionView(
        _: UICollectionView,
        willDisplay _: UICollectionViewCell,
        forItemAt indexPath: IndexPath,
    ) {
        reportMessage(at: indexPath)
    }
}
