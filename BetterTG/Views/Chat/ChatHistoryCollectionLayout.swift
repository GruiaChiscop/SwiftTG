// ChatHistoryCollectionLayout.swift

import UIKit

// MARK: - ChatHistoryCollectionLayout

/// A single-column layout with explicit item heights. Unlike flow-layout automatic sizing, it
/// never asks visible cells to mutate their layout attributes while scrolling.
@MainActor final class ChatHistoryCollectionLayout: UICollectionViewLayout {
    // MARK: Internal

    override var collectionViewContentSize: CGSize {
        contentSize
    }

    var heightProvider: ((Int, CGFloat) -> CGFloat)?
    var itemSpacing: CGFloat = 5

    override func prepare() {
        super.prepare()
        guard let collectionView else { return }
        let metrics = makeMetrics(
            itemCount: collectionView.numberOfItems(inSection: 0),
            boundsSize: collectionView.bounds.size,
        )
        attributes = metrics.attributes
        contentSize = metrics.contentSize
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        attributes.filter { $0.frame.intersects(rect) }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard attributes.indices.contains(indexPath.item) else { return nil }
        return attributes[indexPath.item]
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        guard let collectionView else { return false }
        return collectionView.bounds.size != newBounds.size
    }

    func projectedContentSize(itemCount: Int) -> CGSize {
        guard let collectionView else { return .zero }
        return makeMetrics(itemCount: itemCount, boundsSize: collectionView.bounds.size).contentSize
    }

    func projectedFrame(at index: Int, itemCount: Int) -> CGRect? {
        guard let collectionView, index >= 0, index < itemCount else { return nil }
        return makeMetrics(itemCount: itemCount, boundsSize: collectionView.bounds.size)
            .attributes[index]
            .frame
    }

    func invalidateLayout(contentOffsetAdjustment: CGPoint) {
        let context = UICollectionViewLayoutInvalidationContext()
        context.contentOffsetAdjustment = contentOffsetAdjustment
        invalidateLayout(with: context)
    }

    // MARK: Private

    private struct Metrics {
        let attributes: [UICollectionViewLayoutAttributes]
        let contentSize: CGSize
    }

    private var attributes = [UICollectionViewLayoutAttributes]()
    private var contentSize = CGSize.zero

    private func makeMetrics(itemCount: Int, boundsSize: CGSize) -> Metrics {
        let width = boundsSize.width
        var heights = [CGFloat]()
        heights.reserveCapacity(itemCount)
        for index in 0..<itemCount {
            heights.append(max(1, heightProvider?(index, width) ?? 1))
        }

        let rowsHeight = heights.reduce(0, +)
        let spacingHeight = itemSpacing * CGFloat(max(0, itemCount - 1))
        let naturalHeight = rowsHeight + spacingHeight
        var y = max(0, boundsSize.height - naturalHeight)

        var projectedAttributes = [UICollectionViewLayoutAttributes]()
        projectedAttributes.reserveCapacity(itemCount)
        for (index, height) in heights.enumerated() {
            let indexPath = IndexPath(item: index, section: 0)
            let itemAttributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
            itemAttributes.frame = CGRect(x: 0, y: y, width: width, height: height)
            projectedAttributes.append(itemAttributes)
            y += height + itemSpacing
        }

        return Metrics(
            attributes: projectedAttributes,
            contentSize: CGSize(width: width, height: max(boundsSize.height, naturalHeight)),
        )
    }
}
