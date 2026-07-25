// Text.swift

import SwiftUI
import TDLibKit

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
        attributedString.addAttributes([
            .foregroundColor: UIColor.link,
            .link: link.url,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ], range: range)
    }

    if withDate {
        attributedString.append(NSMutableAttributedString.dateString)
    }

    return AttributedString(attributedString)
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
    let attributedText = NSAttributedString(text)
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

    if let url = attributes[.link] as? URL {
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
