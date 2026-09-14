// TelegramNetworkUsageSettingsTests.swift

@testable import BetterTG
import TDLibKit
import Testing

struct TelegramNetworkUsageSettingsTests {
    @Test func `file types map to the expected categories`() {
        #expect(TelegramNetworkUsageCategory(fileType: .fileTypePhoto) == .photos)
        #expect(TelegramNetworkUsageCategory(fileType: .fileTypeProfilePhoto) == .avatars)
        #expect(TelegramNetworkUsageCategory(fileType: .fileTypeVideo) == .videos)
        #expect(TelegramNetworkUsageCategory(fileType: .fileTypeVoiceNote) == .voiceMessages)
        #expect(TelegramNetworkUsageCategory(fileType: .fileTypeVideoNote) == .videoMessages)
        #expect(TelegramNetworkUsageCategory(fileType: .fileTypeDocument) == .files)
        #expect(TelegramNetworkUsageCategory(fileType: .fileTypeAudio) == .music)
        #expect(TelegramNetworkUsageCategory(fileType: .fileTypeSticker) == .stickers)
        #expect(TelegramNetworkUsageCategory(fileType: .fileTypeAnimation) == .animations)
        #expect(TelegramNetworkUsageCategory(fileType: .fileTypeWallpaper) == .wallpaper)
        #expect(TelegramNetworkUsageCategory(fileType: .fileTypeSecret) == .other)
        #expect(TelegramNetworkUsageCategory(fileType: nil) == .other)
    }

    @Test func `scope filters by network type, with roaming and unknown types bucketed as mobile`() {
        #expect(TelegramNetworkUsageScope.wifi.matches(.networkTypeWiFi))
        #expect(!TelegramNetworkUsageScope.wifi.matches(.networkTypeMobile))
        #expect(TelegramNetworkUsageScope.mobile.matches(.networkTypeMobile))
        #expect(TelegramNetworkUsageScope.mobile.matches(.networkTypeMobileRoaming))
        #expect(TelegramNetworkUsageScope.mobile.matches(.networkTypeOther))
        #expect(!TelegramNetworkUsageScope.mobile.matches(.networkTypeWiFi))
        #expect(TelegramNetworkUsageScope.all.matches(.networkTypeWiFi))
        #expect(TelegramNetworkUsageScope.all.matches(.networkTypeMobile))
    }

    @Test func `rows aggregate entries by category within the selected scope`() {
        let statistics = NetworkStatistics(
            entries: [
                .networkStatisticsEntryFile(NetworkStatisticsEntryFile(
                    fileType: .fileTypePhoto, networkType: .networkTypeWiFi, receivedBytes: 100, sentBytes: 10,
                )),
                .networkStatisticsEntryFile(NetworkStatisticsEntryFile(
                    fileType: .fileTypePhoto, networkType: .networkTypeMobile, receivedBytes: 200, sentBytes: 20,
                )),
                .networkStatisticsEntryFile(NetworkStatisticsEntryFile(
                    fileType: .fileTypeVideo, networkType: .networkTypeWiFi, receivedBytes: 5000, sentBytes: 0,
                )),
                .networkStatisticsEntryCall(NetworkStatisticsEntryCall(
                    duration: 60, networkType: .networkTypeWiFi, receivedBytes: 300, sentBytes: 300,
                )),
            ],
            sinceDate: 0,
        )

        let allRows = TelegramNetworkUsageStore.rows(from: statistics, scope: .all)
        #expect(allRows.first?.category == .videos)
        let photosAll = allRows.first { $0.category == .photos }
        #expect(photosAll?.totalBytes == 330)

        let wifiRows = TelegramNetworkUsageStore.rows(from: statistics, scope: .wifi)
        let photosWifi = wifiRows.first { $0.category == .photos }
        #expect(photosWifi?.totalBytes == 110)
        #expect(wifiRows.contains { $0.category == .calls })

        let mobileRows = TelegramNetworkUsageStore.rows(from: statistics, scope: .mobile)
        #expect(mobileRows.count == 1)
        #expect(mobileRows.first?.category == .photos)
        #expect(mobileRows.first?.totalBytes == 220)
    }
}
