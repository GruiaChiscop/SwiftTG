// TelegramStickerSuggestionQuery.swift

import Foundation

enum TelegramStickerSuggestionQuery {
    // MARK: Internal

    static func emoji(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 1, let character = trimmed.first, isEmoji(character) else { return nil }
        return trimmed
    }

    // MARK: Private

    private static func isEmoji(_ character: Character) -> Bool {
        guard let firstScalar = character.unicodeScalars.first else { return false }
        return firstScalar.properties.isEmoji && (firstScalar.value > 0x238C || character.unicodeScalars.count > 1)
    }
}
