// TelegramTextFormatting.swift

import Foundation
import TDLibKit

// MARK: - TelegramTextLink

struct TelegramTextLink: Equatable, Identifiable {
    let offset: Int
    let length: Int
    let displayedText: String
    let url: URL

    var id: String {
        "\(offset):\(length):\(url.absoluteString)"
    }
}

// MARK: - TelegramTextFormatting

enum TelegramTextFormatting {
    // MARK: Internal

    static func addingAutomaticEntities(
        service: any TelegramService,
        to formattedText: FormattedText,
    ) async -> FormattedText {
        guard !formattedText.text.isEmpty,
              let automatic = try? await service.getTextEntities(text: formattedText.text).entities
        else { return formattedText }

        return merging(automaticEntities: automatic, into: formattedText)
    }

    static func merging(
        automaticEntities: [TextEntity],
        into formattedText: FormattedText,
    ) -> FormattedText {
        var entities = formattedText.entities

        for automatic in automaticEntities {
            guard !entities.contains(automatic),
                  !entities.contains(where: { existing in
                      rangesOverlap(existing, automatic) && !canOverlapAutomaticEntity(existing.type)
                  })
            else { continue }
            entities.append(automatic)
        }

        entities.sort {
            if $0.offset != $1.offset {
                return $0.offset < $1.offset
            }
            return $0.length > $1.length
        }
        return FormattedText(entities: entities, text: formattedText.text)
    }

    static func links(in formattedText: FormattedText) -> [TelegramTextLink] {
        formattedText.entities.compactMap { entity in
            guard let displayedText = substring(
                formattedText.text,
                offset: entity.offset,
                length: entity.length,
            ),
                let url = linkURL(for: entity.type, displayedText: displayedText)
            else { return nil }

            return TelegramTextLink(
                offset: entity.offset,
                length: entity.length,
                displayedText: displayedText,
                url: url,
            )
        }
    }

    static func accessibilityDestination(for link: TelegramTextLink) -> String? {
        guard let scheme = link.url.scheme?.lowercased() else { return nil }
        switch scheme {
        case "http", "https":
            guard let host = link.url.host,
                  !link.displayedText.localizedCaseInsensitiveContains(host)
            else { return nil }
            return host
        default:
            return nil
        }
    }

    // MARK: Private

    private static func rangesOverlap(_ lhs: TextEntity, _ rhs: TextEntity) -> Bool {
        max(lhs.offset, rhs.offset) < min(lhs.offset + lhs.length, rhs.offset + rhs.length)
    }

    private static func canOverlapAutomaticEntity(_ type: TextEntityType) -> Bool {
        switch type {
        case .textEntityTypeBlockQuote,
             .textEntityTypeBold,
             .textEntityTypeExpandableBlockQuote,
             .textEntityTypeItalic,
             .textEntityTypeSpoiler,
             .textEntityTypeStrikethrough,
             .textEntityTypeUnderline:
            true
        default:
            false
        }
    }

    private static func linkURL(
        for type: TextEntityType,
        displayedText: String,
    ) -> URL? {
        let value: String
        switch type {
        case .textEntityTypeEmailAddress:
            value = "mailto:\(displayedText)"
        case .textEntityTypeMention:
            value = "https://t.me/\(displayedText.dropFirst())"
        case .textEntityTypePhoneNumber:
            let number = displayedText.filter { $0.isNumber || $0 == "+" }
            value = "tel:\(number)"
        case .textEntityTypeTextUrl(let textURL):
            value = normalizedURLString(textURL.url)
        case .textEntityTypeUrl:
            value = normalizedURLString(displayedText)
        case .textEntityTypeDateTime(let dateTime):
            value = "calendar://\(dateTime.unixTime)"
        default:
            return nil
        }
        return URL(string: value)
    }

    private static func normalizedURLString(_ value: String) -> String {
        if let scheme = URLComponents(string: value)?.scheme, !scheme.isEmpty {
            return value
        }
        return "https://\(value)"
    }

    private static func substring(_ text: String, offset: Int, length: Int) -> String? {
        guard offset >= 0, length >= 0, offset + length <= text.utf16.count else { return nil }
        let utf16Start = text.utf16.index(text.utf16.startIndex, offsetBy: offset)
        let utf16End = text.utf16.index(utf16Start, offsetBy: length)
        guard let start = String.Index(utf16Start, within: text),
              let end = String.Index(utf16End, within: text)
        else { return nil }
        return String(text[start..<end])
    }
}
