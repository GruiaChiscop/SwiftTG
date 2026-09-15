// TelegramAutoDownloadSettingsTests.swift

@testable import BetterTG
import TDLibKit
import Testing

struct TelegramAutoDownloadSettingsTests {
    /// Regression test: TDLib's own `getAutoDownloadSettingsPresets()` was used as the source of
    /// these caps, and its Wi-Fi preset's `maxOtherFileSize` turned out permissive enough to
    /// auto-download several-hundred-MB files without a tap. These numbers must stay hardcoded and
    /// match Unigram's own (another TDLib-based client) `AutoDownloadSettings.Default` - 10 MB
    /// video, 3 MB "other", flat across every network type - not whatever TDLib's server-side
    /// preset happens to return.
    @Test func `default settings use fixed, conservative caps rather than TDLib's own presets`() {
        for type in [NetworkType.networkTypeWiFi, .networkTypeMobile, .networkTypeMobileRoaming] {
            let settings = TelegramAutoDownloadStore.defaultSettings(for: type)
            #expect(settings.isAutoDownloadEnabled)
            #expect(settings.maxVideoFileSize == 10_485_760)
            #expect(settings.maxOtherFileSize == 3_145_728)
            #expect(settings.maxPhotoFileSize == 1_048_576)
        }
    }

    @Test func `a multi-hundred-megabyte document is blocked by the default cap`() {
        let settings = TelegramAutoDownloadStore.defaultSettings(for: .networkTypeWiFi)
        #expect(!TelegramAutoDownloadPolicy.shouldAutoDownload(
            kind: .document,
            fileSize: 300 * 1024 * 1024,
            settings: settings,
        ))
    }
}
