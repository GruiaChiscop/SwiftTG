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
        Text(macAttributedString(formattedText))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }
}

func macAttributedString(_ formattedText: FormattedText) -> AttributedString {
    AttributedString(macNSAttributedString(formattedText))
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
    if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
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
