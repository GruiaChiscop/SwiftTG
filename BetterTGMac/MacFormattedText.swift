// MacFormattedText.swift

import AppKit
import SwiftUI
import TDLibKit

// MARK: - MacFormattedTextView

/// Native SwiftUI text keeps selection and attributed links without putting an NSTextView inside
/// every message row. In particular, this avoids synchronous `ensureLayout` calls whenever the
/// surrounding list asks for a row's size while scrolling.
struct MacFormattedTextView: View {
    let formattedText: FormattedText

    var body: some View {
        Text(MacFormattedTextCache.shared.attributedString(for: formattedText))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }
}

func macAttributedString(_ formattedText: FormattedText) -> AttributedString {
    MacFormattedTextCache.shared.attributedString(for: formattedText)
}

/// Composer conversion intentionally keeps explicit Telegram links as inert metadata instead of
/// AppKit links. A URL must remain editable text in the composer and only become interactive after
/// the message is sent, matching the iOS composer.
func macComposerAttributedString(_ formattedText: FormattedText) -> NSAttributedString {
    let attributed = NSMutableAttributedString(
        string: formattedText.text,
        attributes: macComposerDefaultAttributes,
    )

    for entity in formattedText.entities {
        let range = NSRange(location: entity.offset, length: entity.length)
        guard NSMaxRange(range) <= attributed.length else { continue }

        switch entity.type {
        case .textEntityTypeBold:
            macApplyFontTrait(.boldFontMask, to: range, in: attributed)
        case .textEntityTypeItalic:
            macApplyFontTrait(.italicFontMask, to: range, in: attributed)
        case .textEntityTypeCode, .textEntityTypePre, .textEntityTypePreCode:
            macApplyMonospacedFont(to: range, in: attributed)
        case .textEntityTypeUnderline:
            attributed.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        case .textEntityTypeStrikethrough:
            attributed.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        case .textEntityTypeSpoiler:
            attributed.addAttribute(.backgroundColor, value: NSColor.systemGray, range: range)
        case .textEntityTypeTextUrl(let value):
            attributed.addAttribute(macTelegramTextURLAttribute, value: value.url as NSString, range: range)
        default:
            break
        }
    }

    return attributed
}

func macComposerFormattedText(
    _ attributedText: NSAttributedString,
    trimmingWhitespace: Bool = false,
) -> FormattedText {
    let attributed = trimmingWhitespace
        ? macTrimmedAttributedString(attributedText)
        : attributedText
    var entities = [TextEntity]()

    attributed.enumerateAttributes(
        in: NSRange(location: 0, length: attributed.length),
    ) { attributes, range, _ in
        if let font = attributes[.font] as? NSFont {
            let traits = NSFontManager.shared.traits(of: font)
            if traits.contains(.boldFontMask) {
                entities.append(TextEntity(length: range.length, offset: range.location, type: .textEntityTypeBold))
            }
            if traits.contains(.italicFontMask) {
                entities.append(TextEntity(length: range.length, offset: range.location, type: .textEntityTypeItalic))
            }
            if font.fontDescriptor.symbolicTraits.contains(.monoSpace) {
                entities.append(TextEntity(length: range.length, offset: range.location, type: .textEntityTypeCode))
            }
        }

        if macAttributeIsEnabled(attributes[.underlineStyle]) {
            entities.append(TextEntity(length: range.length, offset: range.location, type: .textEntityTypeUnderline))
        }
        if macAttributeIsEnabled(attributes[.strikethroughStyle]) {
            entities.append(TextEntity(
                length: range.length,
                offset: range.location,
                type: .textEntityTypeStrikethrough,
            ))
        }
        if attributes[.backgroundColor] != nil {
            entities.append(TextEntity(length: range.length, offset: range.location, type: .textEntityTypeSpoiler))
        }

        let explicitURL: String? =
            if let value = attributes[macTelegramTextURLAttribute] as? String {
                value
            } else if let value = attributes[macTelegramTextURLAttribute] as? NSString {
                value as String
            } else if let value = attributes[.link] as? URL {
                value.absoluteString
            } else if let value = attributes[.link] as? String {
                value
            } else {
                nil
            }
        if let explicitURL, !explicitURL.isEmpty {
            entities.append(TextEntity(
                length: range.length,
                offset: range.location,
                type: .textEntityTypeTextUrl(.init(url: explicitURL)),
            ))
        }
    }

    return FormattedText(
        entities: macMergeAdjacentEntities(entities),
        text: attributed.string,
    )
}

// MARK: - MacFormattedTextCache

/// SwiftUI can reevaluate a message row whenever asynchronously loaded metadata changes. Keep the
/// comparatively expensive link detection and attributed-string construction out of those redraws.
private final class MacFormattedTextCache {
    // MARK: Internal

    static let shared = MacFormattedTextCache()

    func attributedString(for formattedText: FormattedText) -> AttributedString {
        let key = Key(formattedText)
        if let cached = values.object(forKey: key) {
            return cached.value
        }

        let value = AttributedString(macNSAttributedString(formattedText))
        values.setObject(Value(value), forKey: key)
        return value
    }

    // MARK: Private

    private final class Key: NSObject {
        // MARK: Lifecycle

        init(_ formattedText: FormattedText) {
            self.formattedText = formattedText
        }

        // MARK: Internal

        override var hash: Int {
            formattedText.hashValue
        }

        override func isEqual(_ object: Any?) -> Bool {
            guard let other = object as? Key else { return false }
            return formattedText == other.formattedText
        }

        // MARK: Private

        private let formattedText: FormattedText
    }

    private final class Value {
        // MARK: Lifecycle

        init(_ value: AttributedString) {
            self.value = value
        }

        // MARK: Internal

        let value: AttributedString
    }

    private let values: NSCache<Key, Value> = {
        let cache = NSCache<Key, Value>()
        cache.countLimit = 512
        return cache
    }()
}

func macNSAttributedString(_ formattedText: FormattedText) -> NSAttributedString {
    let attributed = NSMutableAttributedString(
        string: formattedText.text,
        attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: NSColor.labelColor,
        ],
    )
    let fullRange = NSRange(location: 0, length: attributed.length)
    if let detector = macLinkDetector {
        detector.enumerateMatches(in: formattedText.text, range: fullRange) { match, _, _ in
            guard let match, let url = match.url else { return }
            attributed.addAttribute(.link, value: url, range: match.range)
        }
    }

    for entity in formattedText.entities {
        let range = NSRange(location: entity.offset, length: entity.length)
        guard NSMaxRange(range) <= attributed.length else { continue }
        switch entity.type {
        case .textEntityTypeBold:
            attributed.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize), range: range)
        case .textEntityTypeCode, .textEntityTypePre, .textEntityTypePreCode:
            attributed.addAttribute(
                .font,
                value: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
                range: range,
            )
        case .textEntityTypeItalic:
            attributed.addAttribute(
                .font,
                value: NSFontManager.shared.convert(
                    NSFont.systemFont(ofSize: NSFont.systemFontSize),
                    toHaveTrait: .italicFontMask,
                ),
                range: range,
            )
        case .textEntityTypeSpoiler:
            attributed.addAttribute(.backgroundColor, value: NSColor.gray, range: range)
        case .textEntityTypeStrikethrough:
            attributed.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        case .textEntityTypeUnderline:
            attributed.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        default:
            break
        }
    }

    for link in TelegramTextFormatting.links(in: formattedText) {
        let range = NSRange(location: link.offset, length: link.length)
        guard NSMaxRange(range) <= attributed.length else { continue }
        attributed.addAttribute(.link, value: link.url, range: range)
    }
    return attributed
}

private let macLinkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

let macComposerDefaultAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.preferredFont(forTextStyle: .body),
    .foregroundColor: NSColor.labelColor,
]

private let macTelegramTextURLAttribute = NSAttributedString.Key("BetterTG.TelegramTextURL")

private func macApplyFontTrait(
    _ trait: NSFontTraitMask,
    to range: NSRange,
    in attributed: NSMutableAttributedString,
) {
    attributed.enumerateAttribute(.font, in: range) { value, subrange, _ in
        let font = value as? NSFont ?? NSFont.preferredFont(forTextStyle: .body)
        let converted = NSFontManager.shared.convert(font, toHaveTrait: trait)
        attributed.addAttribute(.font, value: converted, range: subrange)
    }
}

private func macApplyMonospacedFont(to range: NSRange, in attributed: NSMutableAttributedString) {
    attributed.enumerateAttribute(.font, in: range) { value, subrange, _ in
        let current = value as? NSFont ?? NSFont.preferredFont(forTextStyle: .body)
        let traits = NSFontManager.shared.traits(of: current)
        let weight: NSFont.Weight = traits.contains(.boldFontMask) ? .bold : .regular
        var font = NSFont.monospacedSystemFont(ofSize: current.pointSize, weight: weight)
        if traits.contains(.italicFontMask) {
            font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        }
        attributed.addAttribute(.font, value: font, range: subrange)
    }
}

private func macAttributeIsEnabled(_ value: Any?) -> Bool {
    if let value = value as? NSNumber {
        return value.intValue != 0
    }
    if let value = value as? Int {
        return value != 0
    }
    return false
}

private func macTrimmedAttributedString(_ value: NSAttributedString) -> NSAttributedString {
    let string = value.string as NSString
    let visibleCharacters = CharacterSet.whitespacesAndNewlines.inverted
    let first = string.rangeOfCharacter(from: visibleCharacters)
    guard first.location != NSNotFound else {
        return NSAttributedString(string: "", attributes: macComposerDefaultAttributes)
    }
    let last = string.rangeOfCharacter(from: visibleCharacters, options: .backwards)
    let range = NSRange(location: first.location, length: NSMaxRange(last) - first.location)
    return value.attributedSubstring(from: range)
}

private func macMergeAdjacentEntities(_ entities: [TextEntity]) -> [TextEntity] {
    var merged = [TextEntity]()
    for entity in entities.sorted(by: {
        if $0.offset != $1.offset {
            return $0.offset < $1.offset
        }
        return $0.length < $1.length
    }) {
        if let index = merged.lastIndex(where: {
            $0.type == entity.type && $0.offset + $0.length == entity.offset
        }) {
            let previous = merged[index]
            merged[index] = TextEntity(
                length: previous.length + entity.length,
                offset: previous.offset,
                type: previous.type,
            )
        } else if !merged.contains(entity) {
            merged.append(entity)
        }
    }
    return merged.sorted {
        if $0.offset != $1.offset {
            return $0.offset < $1.offset
        }
        return $0.length > $1.length
    }
}
