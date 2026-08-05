// TelegramStickerCreation.swift

import Foundation
import TDLibKit

// MARK: - TelegramStickerCreationDraft

struct TelegramStickerCreationDraft: Equatable, Sendable {
    static let maximumEmojiLength = 20

    var emojis = ""

    var isValid: Bool {
        (try? validate()) != nil
    }

    /// Keeps only characters that are actually emoji - used to filter the emoji field as the user
    /// types, so it can't end up holding plain text in the first place.
    static func filteredToEmoji(_ text: String) -> String {
        String(text.filter(\.isEmoji))
    }

    func validate() throws -> String {
        let trimmedEmojis = emojis.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmojis.isEmpty else { throw TelegramStickerCreationError.emojiRequired }
        guard trimmedEmojis.count <= Self.maximumEmojiLength else { throw TelegramStickerCreationError.emojiTooLong }
        guard trimmedEmojis.allSatisfy(\.isEmoji) else { throw TelegramStickerCreationError.emojiMustBeEmoji }
        return trimmedEmojis
    }
}

// MARK: - TelegramStickerCreationError

enum TelegramStickerCreationError: Swift.Error, Equatable, LocalizedError {
    case emojiRequired
    case emojiTooLong
    case emojiMustBeEmoji
    case couldNotSuggestName
    case noAvailableNameFound
    case invalidTitleForName
    case createdSetHadNoStickers

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .emojiRequired:
            "Enter at least one emoji for this sticker."
        case .emojiTooLong:
            "The emoji can have at most \(TelegramStickerCreationDraft.maximumEmojiLength) characters."
        case .emojiMustBeEmoji:
            "The sticker's emoji field can only contain emoji."
        case .couldNotSuggestName:
            "Telegram couldn't suggest a link for this sticker pack."
        case .noAvailableNameFound:
            "Couldn't find an available link for this sticker pack."
        case .invalidTitleForName:
            "Telegram couldn't create a sticker pack with that name."
        case .createdSetHadNoStickers:
            "Telegram created the sticker pack but didn't return the sticker."
        }
    }
}

// MARK: - TelegramStickerCreation

enum TelegramStickerCreation {
    // MARK: Internal

    /// Cropping/encoding is the caller's job (see `TelegramStickerCropRendering`) - this takes the
    /// final 512x512 PNG bytes and an emoji, and drives the whole TDLib pipeline. No title/pack
    /// name is ever asked of the user - matches Telegram's own "quick sticker" flow (its Sticker
    /// Editor doesn't ask for a pack name either): the first sticker silently creates a pack named
    /// after the user, and every sticker after that gets added to that same pack via
    /// `addStickerToSet` instead of creating a new one each time.
    static func createOrAddSticker(
        draft: TelegramStickerCreationDraft,
        pngData: Data,
        service: any TelegramService,
    ) async throws -> StickerSet {
        let emojis = try draft.validate()

        let fileURL = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).png")
        try pngData.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let uploadedFile = try await service.uploadStickerFile(
            sticker: .inputFileLocal(.init(path: fileURL.path)),
            stickerFormat: .stickerFormatWebp,
            userId: nil,
        )

        let newSticker = NewSticker(
            emojis: emojis,
            format: .stickerFormatWebp,
            keywords: [],
            maskPosition: nil,
            sticker: .inputFileId(.init(id: uploadedFile.id)),
        )

        if let existingName = TelegramStickerPackName.stored,
           let stickerSet = try? await addToExistingPack(name: existingName, sticker: newSticker, service: service)
        {
            return stickerSet
        }

        // No pack yet (or the stored one no longer exists/is reachable) - create a fresh one, named
        // after the user, and remember its name for next time.
        let stickerSet = try await createFreshPack(sticker: newSticker, service: service)
        TelegramStickerPackName.stored = stickerSet.name
        return stickerSet
    }

    static func resolveAvailableName(
        title: String,
        service: any TelegramService,
        maxAttempts: Int = 20,
    ) async throws -> String {
        try await resolveAvailableName(
            suggestName: { try await service.getSuggestedStickerSetName(title: title).text },
            checkName: { try await service.checkStickerSetName(name: $0) },
            maxAttempts: maxAttempts,
        )
    }

    /// The actual collision-retry loop, expressed over plain closures rather than `any
    /// TelegramService` - `TelegramService` is a ~150-method protocol, so a real conformer isn't a
    /// reasonable thing to stub out just for this one loop; closures let it be unit tested directly.
    static func resolveAvailableName(
        suggestName: () async throws -> String,
        checkName: (String) async throws -> CheckStickerSetNameResult,
        maxAttempts: Int = 20,
    ) async throws -> String {
        let suggested = try await suggestName()
        guard !suggested.isEmpty else { throw TelegramStickerCreationError.couldNotSuggestName }

        var candidate = suggested
        for attempt in 0..<maxAttempts {
            switch try await checkName(candidate) {
            case .checkStickerSetNameResultOk:
                return candidate
            case .checkStickerSetNameResultNameOccupied:
                candidate = "\(suggested)\(attempt + 2)"
            case .checkStickerSetNameResultNameInvalid:
                throw TelegramStickerCreationError.invalidTitleForName
            }
        }
        throw TelegramStickerCreationError.noAvailableNameFound
    }

    // MARK: Private

    private static func addToExistingPack(
        name: String,
        sticker: NewSticker,
        service: any TelegramService,
    ) async throws -> StickerSet {
        _ = try await service.addStickerToSet(name: name, sticker: sticker, userId: nil)
        let stickerSet = try await service.searchStickerSet(ignoreCache: true, name: name)
        await bestEffortInstall(stickerSet, service: service)
        return stickerSet
    }

    private static func createFreshPack(sticker: NewSticker, service: any TelegramService) async throws -> StickerSet {
        let currentUser = try? await service.getMe()
        let title = currentUser.map { "\($0.firstName)’s Stickers" } ?? "My Stickers"
        let name = try await resolveAvailableName(title: title, service: service)

        let stickerSet = try await service.createNewStickerSet(
            name: name,
            needsRepainting: false,
            source: "",
            stickerType: .stickerTypeRegular,
            stickers: [sticker],
            title: title,
            userId: nil,
        )
        guard !stickerSet.stickers.isEmpty else { throw TelegramStickerCreationError.createdSetHadNoStickers }
        await bestEffortInstall(stickerSet, service: service)
        return stickerSet
    }

    private static func bestEffortInstall(_ stickerSet: StickerSet, service: any TelegramService) async {
        guard !stickerSet.isInstalled else { return }
        // Best-effort: the set already exists at this point, so a failure here shouldn't read as
        // "creation failed" to the user.
        _ = try? await service.changeStickerSet(isArchived: false, isInstalled: true, setId: stickerSet.id)
    }
}

// MARK: - TelegramStickerPackName

/// Remembers the name (TDLib's short-link identifier, not the display title) of the sticker pack
/// this device's "quick stickers" get added to, so repeated sticker creation doesn't spawn a new
/// pack every time. Deliberately per-device (`UserDefaults.standard`, the same pattern
/// `RootVM.loggedIn` uses) rather than synced - each installed client just creates its own pack the
/// first time, same as Telegram's own behavior across separate devices/apps.
enum TelegramStickerPackName {
    // MARK: Internal

    static var stored: String? {
        get { UserDefaults.standard.string(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    // MARK: Private

    private static let key = "TelegramStickerCreation.packName"
}

// MARK: - Character + isEmoji

private extension Character {
    /// True for genuine emoji (including multi-scalar sequences like flags, skin tones, and ZWJ
    /// combos) - excludes plain ASCII characters that Unicode happens to also flag `isEmoji` on
    /// their own (e.g. digits, `#`, `*`), which aren't emoji unless combined with a variation
    /// selector or similar.
    var isEmoji: Bool {
        guard let firstScalar = unicodeScalars.first else { return false }
        return firstScalar.properties.isEmoji && (firstScalar.value > 0x238C || unicodeScalars.count > 1)
    }
}
