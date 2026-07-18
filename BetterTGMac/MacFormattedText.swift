// MacFormattedText.swift

import AppKit
import SwiftUI
import TDLibKit

// MARK: - MacFormattedTextView

struct MacFormattedTextView: NSViewRepresentable {
    // MARK: Internal

    let formattedText: FormattedText

    func makeNSView(context _: Context) -> NSTextView {
        let textView = MessageTextView(frame: .zero)
        textView.drawsBackground = false
        textView.isEditable = false
        textView.isHorizontallyResizable = false
        textView.isRichText = true
        textView.isSelectable = true
        textView.isVerticallyResizable = true
        textView.textContainerInset = .zero
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.lineBreakMode = .byWordWrapping
        textView.textContainer?.widthTracksTextView = true
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        update(textView)
        return textView
    }

    func updateNSView(_ textView: NSTextView, context _: Context) {
        update(textView)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView textView: NSTextView,
        context _: Context,
    ) -> CGSize? {
        let width = max(1, proposal.width ?? 480)
        guard let textContainer = textView.textContainer else { return nil }
        textContainer.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        textView.layoutManager?.ensureLayout(for: textContainer)
        guard let usedRect = textView.layoutManager?.usedRect(for: textContainer) else { return nil }
        return CGSize(width: min(width, ceil(usedRect.width)), height: max(1, ceil(usedRect.height)))
    }

    // MARK: Private

    private func update(_ textView: NSTextView) {
        let value = macNSAttributedString(formattedText)
        if textView.attributedString() != value {
            textView.textStorage?.setAttributedString(value)
        }
    }
}

/// Links remain clickable and text remains selectable, while vertical arrows
/// are handed back to the enclosing native message table.
private final class MessageTextView: NSTextView {
    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .function])
        if modifiers.isEmpty,
           event.keyCode == 125 || event.keyCode == 126
        {
            if let tableView = enclosingMessageTable {
                window?.makeFirstResponder(tableView)
                tableView.keyDown(with: event)
            } else {
                super.keyDown(with: event)
            }
            return
        }
        super.keyDown(with: event)
    }

    private var enclosingMessageTable: MessageNSTableView? {
        var candidate = superview
        while let view = candidate {
            if let tableView = view as? MessageNSTableView { return tableView }
            candidate = view.superview
        }
        return nil
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
