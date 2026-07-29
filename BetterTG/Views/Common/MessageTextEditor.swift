// MessageTextEditor.swift

import SwiftUI

// MARK: - MessageUITextView

private final class MessageUITextView: UITextView {
    var onSubmit: (() -> Void)?
    var onPasteImages: (([SelectedImage]) -> Void)?

    override var keyCommands: [UIKeyCommand]? {
        (super.keyCommands ?? []) + [
            UIKeyCommand(
                input: "\r",
                modifierFlags: [],
                action: #selector(submit(_:)),
            ),
        ]
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        guard action == #selector(paste(_:)), UIPasteboard.general.hasImages else {
            return super.canPerformAction(action, withSender: sender)
        }
        return onPasteImages != nil
    }

    override func paste(_ sender: Any?) {
        guard UIPasteboard.general.hasImages else {
            super.paste(sender)
            return
        }
        guard let onPasteImages else { return }

        let images = (UIPasteboard.general.images ?? []).compactMap { writeImage($0) }
        guard !images.isEmpty else {
            super.paste(sender)
            return
        }

        onPasteImages(images)
        UIAccessibility.post(
            notification: .announcement,
            argument: images.count == 1 ? "Photo attached" : "\(images.count) photos attached",
        )
    }

    @objc private func submit(_: UIKeyCommand) {
        onSubmit?()
    }
}

// MARK: - MessageUITextViewRepresentable

private struct MessageUITextViewRepresentable: UIViewRepresentable {
    final class Coordinator: NSObject, UITextViewDelegate {
        // MARK: Lifecycle

        init(parent: MessageUITextViewRepresentable) {
            self.parent = parent
        }

        // MARK: Internal

        var parent: MessageUITextViewRepresentable

        func textViewDidChange(_ textView: UITextView) {
            parent.text = AttributedString(textView.attributedText)
        }
    }

    @Binding var text: AttributedString

    let onSubmit: (() -> Void)?
    let onPasteImages: (([SelectedImage]) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> MessageUITextView {
        let textView = MessageUITextView()
        textView.delegate = context.coordinator
        textView.onSubmit = onSubmit
        textView.onPasteImages = onPasteImages
        textView.adjustsFontForContentSizeCategory = true
        textView.allowsEditingTextAttributes = true
        textView.backgroundColor = .clear
        textView.font = .body
        textView.textColor = .white
        textView.tintColor = .link
        textView.typingAttributes = defaultAttributes()
        textView.attributedText = NSAttributedString(text)
        textView.isEditable = true
        textView.isSelectable = true
        textView.isScrollEnabled = true
        textView.showsVerticalScrollIndicator = false
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textView
    }

    func updateUIView(_ textView: MessageUITextView, context: Context) {
        context.coordinator.parent = self
        textView.onSubmit = onSubmit
        textView.onPasteImages = onPasteImages

        let newValue = NSAttributedString(text)
        guard textView.attributedText != newValue else { return }

        let selection = textView.selectedRange
        textView.attributedText = newValue
        textView.selectedRange = NSRange(
            location: min(selection.location, newValue.length),
            length: min(selection.length, max(0, newValue.length - selection.location)),
        )
        if newValue.length == 0 {
            textView.typingAttributes = defaultAttributes()
        }
    }
}

// MARK: - MessageTextEditor

struct MessageTextEditor: View {
    // MARK: Lifecycle

    init(
        _ placeholder: String = "",
        text: Binding<AttributedString>,
        onSubmit: (() -> Void)? = nil,
        onPasteImages: (([SelectedImage]) -> Void)? = nil,
    ) {
        self.placeholder = placeholder
        self._text = text
        self.onSubmit = onSubmit
        self.onPasteImages = onPasteImages
    }

    // MARK: Internal

    var body: some View {
        ZStack(alignment: .topLeading) {
            sizingText

            if text.characters.isEmpty {
                Text(placeholder)
                    .foregroundStyle(.gray)
                    .padding(.leading, 5)
                    .padding(.top, 8)
                    .accessibilityHidden(true)
            }

            MessageUITextViewRepresentable(
                text: $text,
                onSubmit: onSubmit,
                onPasteImages: onPasteImages,
            )
            .accessibilityLabel(placeholder)
        }
        .frame(minHeight: 36, maxHeight: 302)
        .clipped()
    }

    // MARK: Private

    @Binding private var text: AttributedString

    private let placeholder: String
    private let onSubmit: (() -> Void)?
    private let onPasteImages: (([SelectedImage]) -> Void)?

    private var sizingText: some View {
        Text(text.characters.isEmpty ? AttributedString(" ") : text)
            .font(.body)
            .padding(.horizontal, 5)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .opacity(0)
            .accessibilityHidden(true)
    }
}
