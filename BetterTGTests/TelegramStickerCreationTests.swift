// TelegramStickerCreationTests.swift

@testable import BetterTG
import Testing

struct TelegramStickerCreationTests {
    @Test func `draft requires a non-empty emoji`() {
        let draft = TelegramStickerCreationDraft()
        #expect(!draft.isValid)
    }

    @Test func `draft rejects emoji over the length limit`() {
        var draft = TelegramStickerCreationDraft()
        draft.emojis = String(repeating: "1", count: TelegramStickerCreationDraft.maximumEmojiLength + 1)
        #expect(!draft.isValid)
    }

    @Test func `draft rejects plain text that isn't emoji`() {
        var draft = TelegramStickerCreationDraft()
        draft.emojis = "hello"
        #expect(!draft.isValid)
    }

    @Test func `draft is valid with a trimmed emoji`() {
        var draft = TelegramStickerCreationDraft()
        draft.emojis = "  🎉  "
        #expect(draft.isValid)
    }

    @Test func `filtering keeps only emoji characters`() {
        #expect(TelegramStickerCreationDraft.filteredToEmoji("abc🎉123") == "🎉")
        #expect(TelegramStickerCreationDraft.filteredToEmoji("hello world") == "")
        #expect(TelegramStickerCreationDraft.filteredToEmoji("👋🏽😀") == "👋🏽😀")
    }

    @Test func `name resolution returns the suggested name when it's free`() async throws {
        let name = try await TelegramStickerCreation.resolveAvailableName(
            suggestName: { "my_pack" },
            checkName: { _ in .checkStickerSetNameResultOk },
        )
        #expect(name == "my_pack")
    }

    @Test func `name resolution retries with a numeric suffix on collision`() async throws {
        var checkedNames = [String]()
        let name = try await TelegramStickerCreation.resolveAvailableName(
            suggestName: { "my_pack" },
            checkName: { candidate in
                checkedNames.append(candidate)
                return candidate == "my_pack2" ? .checkStickerSetNameResultOk : .checkStickerSetNameResultNameOccupied
            },
        )
        #expect(name == "my_pack2")
        #expect(checkedNames == ["my_pack", "my_pack2"])
    }

    @Test func `name resolution gives up after exhausting all attempts`() async {
        await #expect(throws: TelegramStickerCreationError.noAvailableNameFound) {
            try await TelegramStickerCreation.resolveAvailableName(
                suggestName: { "my_pack" },
                checkName: { _ in .checkStickerSetNameResultNameOccupied },
                maxAttempts: 3,
            )
        }
    }

    @Test func `name resolution fails immediately on an invalid base name, without retrying`() async {
        var checkCount = 0
        await #expect(throws: TelegramStickerCreationError.invalidTitleForName) {
            try await TelegramStickerCreation.resolveAvailableName(
                suggestName: { "🎉🎉🎉" },
                checkName: { _ in
                    checkCount += 1
                    return .checkStickerSetNameResultNameInvalid
                },
            )
        }
        #expect(checkCount == 1)
    }

    @Test func `name resolution fails when no name can be suggested`() async {
        await #expect(throws: TelegramStickerCreationError.couldNotSuggestName) {
            try await TelegramStickerCreation.resolveAvailableName(
                suggestName: { "" },
                checkName: { _ in .checkStickerSetNameResultOk },
            )
        }
    }
}
