// TelegramStorageUsageViewTests.swift

@testable import BetterTG
import TDLibKit
import Testing

struct TelegramStorageUsageViewTests {
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
}
