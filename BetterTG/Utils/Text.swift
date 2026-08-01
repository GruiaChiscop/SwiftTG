// Text.swift

import SwiftUI
import TDLibKit

// MARK: - TelegramTextLinkStyle

enum TelegramTextLinkStyle: Equatable {
    case composer
    case message
}

// MARK: - TelegramTextURLAttribute

private struct TelegramTextURLAttribute: CodableAttributedStringKey, ObjectiveCConvertibleAttributedStringKey {
    typealias ObjectiveCValue = NSString
    typealias Value = String

    static let name = "BetterTG.TelegramTextURL"

    static func objectiveCValue(for value: String) -> NSString {
        value as NSString
    }

    static func value(for object: NSString) -> String {
        object as String
    }
}

private extension AttributeScopes {
    struct BetterTGTextAttributes: AttributeScope {
        let foundation: FoundationAttributes
        let telegramTextURL: TelegramTextURLAttribute
        let uiKit: UIKitAttributes
    }

    var betterTGText: BetterTGTextAttributes.Type { BetterTGTextAttributes.self }
}

let telegramTextURLAttributeKey = NSAttributedString.Key(TelegramTextURLAttribute.name)

func telegramAttributedString(from value: NSAttributedString) -> AttributedString {
    (try? AttributedString(value, including: \.betterTGText)) ?? AttributedString(value)
}

func telegramNSAttributedString(from value: AttributedString) -> NSAttributedString {
    (try? NSAttributedString(value, including: \.betterTGText)) ?? NSAttributedString(value)
}

func defaultAttributes(_ foregroundColor: Color = .white) -> [NSAttributedString.Key: Any] {
    [
        .font: UIFont.body as Any,
        .foregroundColor: UIColor(foregroundColor),
    ]
}

func getAttributedString(
    from formattedText: FormattedText,
    _ foregroundColor: Color = .white,
    withDate: Bool = false,
    linkStyle: TelegramTextLinkStyle = .message,
) -> AttributedString {
    let attributedString = NSMutableAttributedString(
        string: formattedText.text,
        attributes: defaultAttributes(foregroundColor),
    )

    for entity in formattedText.entities {
        setEntity(entity, for: attributedString)
    }

    for link in TelegramTextFormatting.links(in: formattedText) {
        let range = NSRange(location: link.offset, length: link.length)
        guard NSMaxRange(range) <= attributedString.length else { continue }

        if linkStyle == .message {
            attributedString.addAttributes([
                .foregroundColor: UIColor.link,
                .link: link.url,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
            ], range: range)
        } else if formattedText.entities.contains(where: { entity in
            guard entity.offset == link.offset, entity.length == link.length else { return false }
            if case .textEntityTypeTextUrl = entity.type {
                return true
            }
            return false
        }) {
            // Keep an explicit textUrl's destination for a lossless edit, but don't make
            // an automatically detected URL look like a rendered message link.
            attributedString.addAttributes([
                .foregroundColor: UIColor.link,
                telegramTextURLAttributeKey: link.url.absoluteString,
            ], range: range)
        }
    }

    if withDate {
        attributedString.append(NSMutableAttributedString.dateString)
    }

    return telegramAttributedString(from: attributedString)
}

func setEntity(_ entity: TextEntity, for attributedString: NSMutableAttributedString) {
    let range = NSRange(location: entity.offset, length: entity.length)

    switch entity.type {
    case .textEntityTypeBold:
        attributedString.addAttribute(.font, value: UIFont.bold, range: range)
    case .textEntityTypeItalic:
        attributedString.addAttribute(.font, value: UIFont.italic, range: range)
    case .textEntityTypeCode, .textEntityTypePre, .textEntityTypePreCode:
        attributedString.addAttribute(.font, value: UIFont.monospaced, range: range)
    case .textEntityTypeUnderline:
        attributedString.addAttribute(.underlineStyle, value: 1, range: range)
    case .textEntityTypeStrikethrough:
        attributedString.addAttribute(.strikethroughStyle, value: 1, range: range)
    case .textEntityTypeSpoiler:
        attributedString.addAttribute(.backgroundColor, value: UIColor.gray, range: range)
//        case .textEntityTypeCustomEmoji: // (let textEntityTypeCustomEmoji)
//            guard showAnimojis else { break }
//            attributedString.addAttribute(.foregroundColor, value: UIColor.clear, range: range)
    default:
        break
    }
}

func getEntities(from text: AttributedString) -> [TextEntity] {
    var entities = [TextEntity]()
    let attributedText = telegramNSAttributedString(from: text)
    let textRange = NSRange(location: 0, length: attributedText.length)
    attributedText.enumerateAttributes(in: textRange) { attributes, range, _ in
        entities.append(contentsOf: getEntities(from: attributes, using: range))
    }
    return entities.sorted {
        ($0.offset, $0.length) < ($1.offset, $1.length)
    }
}

private func getEntities(
    from attributes: [NSAttributedString.Key: Any],
    using range: NSRange,
) -> [TextEntity] {
    var entities = [TextEntity]()

    if let font = attributes[.font] as? UIFont {
        let traits = font.fontDescriptor.symbolicTraits
        if traits.contains(.traitBold) {
            entities.append(.init(.textEntityTypeBold, range: range))
        }
        if traits.contains(.traitItalic) {
            entities.append(.init(.textEntityTypeItalic, range: range))
        }
        if traits.contains(.traitMonoSpace) {
            entities.append(.init(.textEntityTypeCode, range: range))
        }
    }

    if let urlString = attributes[telegramTextURLAttributeKey] as? String,
       let url = URL(string: urlString)
    {
        entities.append(.init(.textEntityTypeTextUrl(.init(url: url.absoluteString)), range: range))
    } else if let url = attributes[.link] as? URL {
        entities.append(.init(.textEntityTypeTextUrl(.init(url: url.absoluteString)), range: range))
    } else if let urlString = attributes[.link] as? String,
              let url = URL(string: urlString)
    {
        entities.append(.init(.textEntityTypeTextUrl(.init(url: url.absoluteString)), range: range))
    }

    if let style = attributes[.strikethroughStyle] as? NSNumber, style.intValue != 0 {
        entities.append(.init(.textEntityTypeStrikethrough, range: range))
    }
    if let style = attributes[.underlineStyle] as? NSNumber, style.intValue != 0 {
        entities.append(.init(.textEntityTypeUnderline, range: range))
    }
    if attributes[.backgroundColor] != nil {
        entities.append(.init(.textEntityTypeSpoiler, range: range))
    }

    return entities
}

func stringRange(
    for string: String,
    start: Int,
    length: Int,
) -> Range<String.Index> {
    let startIndex = string.utf16.index(string.startIndex, offsetBy: start)
    let endIndex = string.utf16.index(startIndex, offsetBy: length)
    return startIndex..<endIndex
}
