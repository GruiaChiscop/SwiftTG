// TelegramStorageUsageViewTests.swift

@testable import BetterTG
import TDLibKit
import Testing

struct TelegramStorageUsageViewTests {
    // MARK: Internal

    @Test func `category rows group and sum by-file-type entries`() {
        let byFileType = [
            StorageStatisticsByFileType(count: 3, fileType: .fileTypePhoto, size: 300),
            StorageStatisticsByFileType(count: 1, fileType: .fileTypeProfilePhoto, size: 50),
            StorageStatisticsByFileType(count: 2, fileType: .fileTypeVideo, size: 5000),
            StorageStatisticsByFileType(count: 4, fileType: .fileTypeSticker, size: 40),
        ]

        let rows = TelegramStorageUsageStore.categoryRows(byFileType: byFileType)

        #expect(rows.first?.category == .videos)
        let photos = rows.first { $0.category == .photos }
        #expect(photos?.size == 300)
        #expect(photos?.count == 3)
        let avatars = rows.first { $0.category == .avatars }
        #expect(avatars?.size == 50)
        #expect(avatars?.count == 1)
        #expect(rows.first { $0.category == .stickers }?.size == 40)
    }

    @Test func `empty selection shows no row as checked, but still includes everything`() {
        let selection = TelegramStorageCategorySelection()
        #expect(!selection.isSelected(.photos))
        #expect(!selection.isSelected(.videos))
        #expect(selection.isIncluded(.photos))
        #expect(selection.isIncluded(.videos))
    }

    /// Regression test for a real bug: tapping a category then tapping it again returns the
    /// selection to empty, and `isSelected` must NOT fall back to the empty-means-everything rule
    /// the way `isIncluded` does - otherwise that one category reads as permanently "selected" to
    /// VoiceOver no matter how many times it's tapped.
    @Test func `a category returns to unchecked after being toggled back off, even though it's still included`() {
        var selection = TelegramStorageCategorySelection()
        selection.toggle(.photos)
        #expect(selection.isSelected(.photos))

        selection.toggle(.photos)
        #expect(!selection.isSelected(.photos))
        #expect(selection.isIncluded(.photos))
    }

    @Test func `toggling narrows selection to just the tapped categories`() {
        var selection = TelegramStorageCategorySelection()
        selection.toggle(.photos)
        #expect(selection.isSelected(.photos))
        #expect(!selection.isSelected(.videos))

        selection.toggle(.videos)
        #expect(selection.isSelected(.photos))
        #expect(selection.isSelected(.videos))

        selection.toggle(.photos)
        #expect(!selection.isSelected(.photos))
        #expect(selection.isSelected(.videos))
    }

    @Test func `totalSize sums only selected categories, or everything when nothing is selected`() {
        let rows: [(category: TelegramNetworkUsageCategory, size: Int64, count: Int)] = [
            (category: .photos, size: 100, count: 1),
            (category: .videos, size: 5000, count: 1),
            (category: .files, size: 300, count: 1),
        ]

        var selection = TelegramStorageCategorySelection()
        #expect(selection.totalSize(in: rows) == 5400)

        selection.toggle(.photos)
        selection.toggle(.files)
        #expect(selection.totalSize(in: rows) == 400)
    }

    @Test func `fileTypes derived per category never overlap and cover every clearable file type`() {
        let allDerived = TelegramNetworkUsageCategory.allCases.flatMap(\.clearableFileTypes)
        #expect(Set(allDerived).count == allDerived.count)
        #expect(Set(allDerived) == Set(telegramClearableFileTypes))
    }

    @Test func `five or fewer categories never fold, in either chart or list form`() {
        let rows = Self.sizedRows(count: 5)
        let chart = TelegramStorageUsageStore.chartEntries(from: rows, isOtherExpanded: false)
        let displayRows = TelegramStorageUsageStore.splitForDisplay(rows)
        #expect(chart.count == 5)
        #expect(displayRows.shown.count == 5)
        #expect(displayRows.folded.isEmpty)
        #expect(chart.allSatisfy {
            if case .category = $0 {
                true
            } else {
                false
            }
        })
    }

    @Test func `beyond five categories, the chart folds the smallest into one collapsed Other slice`() {
        let rows = Self.sizedRows(count: 8)
        let chart = TelegramStorageUsageStore.chartEntries(from: rows, isOtherExpanded: false)

        #expect(chart.count == 6)
        guard case .grouped(let categories, let size, let count) = chart.last else {
            Issue.record("Expected the last chart entry to be grouped")
            return
        }
        #expect(categories.count == 3)
        #expect(size == rows.suffix(3).reduce(0) { $0 + $1.size })
        #expect(count == rows.suffix(3).reduce(0) { $0 + $1.count })
    }

    @Test func `expanding removes the grouped chart slice entirely, showing every category individually`() {
        let rows = Self.sizedRows(count: 8)
        let chart = TelegramStorageUsageStore.chartEntries(from: rows, isOtherExpanded: true)

        #expect(chart.count == 8)
        #expect(chart.allSatisfy {
            if case .category = $0 {
                true
            } else {
                false
            }
        })
    }

    @Test func `splitForDisplay separates the top 5 from everything else, for a native DisclosureGroup to fold`() {
        let rows = Self.sizedRows(count: 8)
        let displayRows = TelegramStorageUsageStore.splitForDisplay(rows)

        #expect(displayRows.shown.count == 5)
        #expect(displayRows.folded.count == 3)
        #expect(displayRows.shown.map(\.category) == rows.prefix(5).map(\.category))
        #expect(displayRows.folded.map(\.category) == rows.suffix(3).map(\.category))
    }

    // MARK: Private

    /// `count` distinct categories (taken from `allCases`, which has more than 5), each with a
    /// strictly decreasing size so sort order is unambiguous.
    private static func sizedRows(count: Int) -> [(category: TelegramNetworkUsageCategory, size: Int64, count: Int)] {
        Array(TelegramNetworkUsageCategory.allCases.prefix(count)).enumerated().map { index, category in
            (category: category, size: Int64((count - index) * 100), count: index + 1)
        }
    }
}
