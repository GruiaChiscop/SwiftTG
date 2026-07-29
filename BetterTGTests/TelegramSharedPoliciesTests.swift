// TelegramSharedPoliciesTests.swift

@testable import BetterTG
import Foundation
import TDLibKit
import Testing

struct TelegramSharedPoliciesTests {
    @Test func `authentication code length follows TDLib metadata`() {
        let numericCode = AuthenticationCodeType.authenticationCodeTypeSms(.init(length: 6))
        let wordCode = AuthenticationCodeType.authenticationCodeTypeSmsWord(.init(firstLetter: "c"))

        #expect(numericCode.expectedLength == 6)
        #expect(wordCode.expectedLength == nil)
    }

    @Test func `phone numbers are normalized consistently`() {
        #expect(TelegramPhoneNumber.normalized(callingCode: "40", number: "721 234 567") == "+40721234567")
        #expect(TelegramPhoneNumber.normalized(callingCode: "", number: "+44 7700 900123") == "+447700900123")
        #expect(TelegramPhoneNumber.normalized(callingCode: "", number: "7700900123") == nil)
    }

    @Test func `calling code resolution waits while a longer code is possible`() {
        let countries = [
            PhoneNumberInfo(country: "US", phoneNumberPrefix: "1", name: "United States"),
            PhoneNumberInfo(country: "XX", phoneNumberPrefix: "12", name: "Example"),
        ]

        let partial = TelegramPhoneNumber.resolveCallingCode("1", countries: countries, preferredCountryId: nil)
        let preferred = TelegramPhoneNumber.resolveCallingCode("1", countries: countries, preferredCountryId: "US")

        #expect(partial.country?.country == "US")
        #expect(!partial.shouldAdvanceToNumber)
        #expect(preferred.shouldAdvanceToNumber)
    }

    @Test func `chat action policy distinguishes members and creators`() {
        let member = TelegramChatActionPolicy(
            kind: .group,
            membership: .member,
            canBeDeletedOnlyForSelf: true,
            canBeDeletedForAllUsers: false,
        )
        let creator = TelegramChatActionPolicy(
            kind: .channel,
            membership: .creator,
            canBeDeletedOnlyForSelf: false,
            canBeDeletedForAllUsers: true,
        )

        #expect(member.canLeave)
        #expect(!member.canDeleteChat)
        #expect(creator.canDeleteCommunity)
        #expect(creator.deleteActionTitle == "Delete Channel")
    }

    @Test func `chat action policy still allows deleting a group the user is no longer part of`() {
        let stale = TelegramChatActionPolicy(
            kind: .group,
            membership: .notMember,
            canBeDeletedOnlyForSelf: true,
            canBeDeletedForAllUsers: false,
        )
        let unknownMembership = TelegramChatActionPolicy(
            kind: .channel,
            membership: nil,
            canBeDeletedOnlyForSelf: true,
            canBeDeletedForAllUsers: false,
        )

        #expect(!stale.canLeave)
        #expect(stale.canDeleteChat)
        #expect(!unknownMembership.canLeave)
        #expect(unknownMembership.canDeleteChat)
    }

    @Test func `channel subscribers cannot post while owners can`() {
        let subscriber = ChatMemberStatus.chatMemberStatusMember(.init(memberUntilDate: 0))
        let owner = ChatMemberStatus.chatMemberStatusCreator(.init(isAnonymous: false, isMember: true))

        #expect(!telegramCanPostMessages(isChannel: true, status: subscriber))
        #expect(telegramCanPostMessages(isChannel: true, status: owner))
        #expect(telegramCanPostMessages(isChannel: false, status: subscriber))
    }

    @Test func `service sounds are throttled independently`() {
        var policy = TelegramServiceSoundPolicy(minimumInterval: 0.2)
        let start = Date(timeIntervalSince1970: 100)

        let firstDelivered = policy.shouldPlayDelivered(now: start)
        let throttledDelivered = policy.shouldPlayDelivered(now: start.addingTimeInterval(0.1))
        let firstIncoming = policy.shouldPlayIncoming(applicationIsActive: true, isMuted: false, now: start)
        let throttledIncoming = policy.shouldPlayIncoming(
            applicationIsActive: true,
            isMuted: false,
            now: start.addingTimeInterval(0.1),
        )
        let mutedIncoming = policy.shouldPlayIncoming(
            applicationIsActive: true,
            isMuted: true,
            now: start.addingTimeInterval(1),
        )

        #expect(firstDelivered)
        #expect(!throttledDelivered)
        #expect(firstIncoming)
        #expect(!throttledIncoming)
        #expect(!mutedIncoming)
    }

    @Test func `voice note staging and waveform are deterministic`() throws {
        let identifier = try #require(UUID(uuidString: "3DC60D07-67C4-4AA4-BB6B-2F40BE1158B8"))
        let url = TelegramVoiceNoteSending.temporaryFileURL(
            in: URL(filePath: "/tmp/voice-tests"),
            identifier: identifier,
        )

        #expect(url.lastPathComponent == "voice_3DC60D07-67C4-4AA4-BB6B-2F40BE1158B8.ogg")
        #expect(TelegramVoiceNoteSending.waveform(from: [-66, -33]) == Data([4, 0]))
        #expect(TelegramVoiceNoteSending.waveform(from: [-160, -120]).isEmpty)
    }

    /// Regression test for a bug where `MacSessionModel.sendVoiceRecording()` sent `Data()`
    /// unconditionally instead of the recorded amplitude, so every macOS-recorded voice note
    /// showed an empty waveform to every recipient (including other, real Telegram clients).
    /// Reproduces `VoiceNoteRecorder.updatePeak`'s dB formula for a realistic sequence of
    /// recorded sample peaks - the same values macOS's recording timer now samples into
    /// `peakPower` every 50ms - and checks the shared encoder turns them into real, non-empty,
    /// spec-sized waveform data instead of the empty bytes the bug produced.
    @Test func `realistic mac recording samples encode into a non-empty waveform`() {
        func decibels(forPeakSample peak: Int16) -> Float {
            let normalized = max(Float(peak) / Float(Int16.max), 0.000_000_1)
            return 20 * log10(normalized)
        }

        let recordedPeaks: [Int16] = [0, 4000, 12000, 30000, 20000, 500, 0, 8000]
        let simulatedWave = recordedPeaks.map(decibels(forPeakSample:))
        let silentWave = [Float](repeating: decibels(forPeakSample: 0), count: recordedPeaks.count)

        let waveform = TelegramVoiceNoteSending.waveform(from: simulatedWave)

        #expect(!waveform.isEmpty)
        #expect(waveform.count <= 63)
        #expect(TelegramVoiceNoteSending.waveform(from: silentWave).isEmpty)
    }

    @Test func `voice note staging removes a file after send succeeds`() throws {
        let directory = FileManager.default
            .temporaryDirectory
            .appending(path: "BetterTGVoiceNoteStagingTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let staging = TelegramVoiceNoteStaging(directory: directory)
        let fileURL = staging.fileURL()
        try Data([1, 2, 3]).write(to: fileURL)

        staging.register(fileURL: fileURL, chatId: 10, temporaryMessageId: -20)
        staging.messageSendSucceeded(chatId: 10, oldMessageId: -20)

        #expect(!FileManager.default.fileExists(atPath: fileURL.path()))
    }

    @Test func `voice note staging survives failure until retry succeeds`() throws {
        let directory = FileManager.default
            .temporaryDirectory
            .appending(path: "BetterTGVoiceNoteStagingTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let staging = TelegramVoiceNoteStaging(directory: directory)
        let fileURL = staging.fileURL()
        try Data([1, 2, 3]).write(to: fileURL)

        staging.register(fileURL: fileURL, chatId: 10, temporaryMessageId: -20)
        staging.messageSendFailed(chatId: 10, oldMessageId: -20, failedMessageId: -21)
        #expect(FileManager.default.fileExists(atPath: fileURL.path()))

        staging.messageSendSucceeded(chatId: 10, oldMessageId: -21)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path()))
    }

    @Test func `voice note staging removes abandoned old files`() throws {
        let directory = FileManager.default
            .temporaryDirectory
            .appending(path: "BetterTGVoiceNoteStagingTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let staging = TelegramVoiceNoteStaging(directory: directory)
        let fileURL = staging.fileURL()
        try Data([1]).write(to: fileURL)
        let now = Date(timeIntervalSince1970: 200_000)
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-25 * 60 * 60)],
            ofItemAtPath: fileURL.path(),
        )

        _ = TelegramVoiceNoteStaging(directory: directory, now: now)

        #expect(!FileManager.default.fileExists(atPath: fileURL.path()))
    }

    @Test func `notification payload extracts direct chat and message identifiers`() {
        let target = TelegramNotificationPayload.target(from: [
            "thread-id": "chat.12345",
            "msg_id": "678",
        ])

        #expect(target?.chatIds == [12345])
        #expect(target?.messageId == 678)
    }

    @Test func `notification payload extracts peer hints used by Telegram push`() {
        let target = TelegramNotificationPayload.target(from: [
            "from_id": "11",
            "channel_id": "22",
            "aps": [
                "chatId": "33",
            ],
        ])

        #expect(target?.userIds == [11])
        #expect(target?.supergroupIds == [22])
        #expect(target?.chatIds == [33])
    }

    @Test func `notification payload extracts chat identifiers from raw JSON`() {
        let target = TelegramNotificationPayload.target(from: [
            "tg_raw": #"{"update":{"message":{"chat_id":-100123,"id":55}}}"#,
        ])

        #expect(target?.chatIds == [-100_123])
        #expect(target?.messageId == nil)
    }

    @Test func `automatic text entities preserve formatting and detect multiple links`() {
        let text = "😀 Visit https://a.example and https://b.example"
        let nsText = text as NSString
        let firstLinkRange = nsText.range(of: "https://a.example")
        let secondLinkRange = nsText.range(of: "https://b.example")
        let bold = TextEntity(length: firstLinkRange.length, offset: firstLinkRange.location, type: .textEntityTypeBold)
        let links = [firstLinkRange, secondLinkRange].map { range in
            TextEntity(length: range.length, offset: range.location, type: .textEntityTypeUrl)
        }

        let result = TelegramTextFormatting.merging(
            automaticEntities: links,
            into: FormattedText(entities: [bold], text: text),
        )

        #expect(result.entities.contains(bold))
        #expect(result.entities.filter { $0.type == .textEntityTypeUrl } == links)
        #expect(TelegramTextFormatting.links(in: result).map(\.displayedText) == [
            "https://a.example",
            "https://b.example",
        ])
    }

    @Test func `automatic link does not replace an explicit text link`() {
        let text = "Open this page"
        let range = (text as NSString).range(of: "this page")
        let explicitLink = TextEntity(
            length: range.length,
            offset: range.location,
            type: .textEntityTypeTextUrl(.init(url: "https://example.com/custom")),
        )
        let detectedLink = TextEntity(length: range.length, offset: range.location, type: .textEntityTypeUrl)

        let result = TelegramTextFormatting.merging(
            automaticEntities: [detectedLink],
            into: FormattedText(entities: [explicitLink], text: text),
        )

        #expect(result.entities == [explicitLink])
    }
}
