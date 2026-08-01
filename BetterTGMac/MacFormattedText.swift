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
