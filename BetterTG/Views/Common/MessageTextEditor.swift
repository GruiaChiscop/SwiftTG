// MessageTextEditor.swift

import SwiftUI

// MARK: - MessageUITextView

private final class MessageUITextView: UITextView {
    // MARK: Internal

    override var keyCommands: [UIKeyCommand]? {
        (super.keyCommands ?? []) + [
            UIKeyCommand(
                input: "\r",
                modifierFlags: [],
                action: #selector(submit(_:)),
            ),
        ]
    }

    var onSubmit: (() -> Void)?
    var onPasteImages: (([SelectedImage]) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        voiceOverFocusController.viewDidMoveToWindow(self)
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

    func requestVoiceOverFocus() {
        voiceOverFocusController.requestFocus(on: self)
    }

    // MARK: Private

    private let voiceOverFocusController = VoiceOverFocusController()

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
            self.contextID = parent.contextID
        }

        // MARK: Internal

        var parent: MessageUITextViewRepresentable
        var contextID: AnyHashable
        var lastVoiceOverFocusRequest = 0

        func textViewDidChange(_ textView: UITextView) {
            parent.text = telegramAttributedString(from: textView.attributedText)
        }
    }

    @Binding var text: AttributedString

    let contextID: AnyHashable
    let voiceOverFocusRequest: Int
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
        textView.attributedText = telegramNSAttributedString(from: text)
        textView.selectedRange = NSRange(location: textView.attributedText.length, length: 0)
        textView.isEditable = true
        textView.isSelectable = true
        textView.isScrollEnabled = true
        textView.showsVerticalScrollIndicator = false
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textView
    }

    func updateUIView(_ textView: MessageUITextView, context: Context) {
        let contextChanged = context.coordinator.contextID != contextID
        context.coordinator.parent = self
        textView.onSubmit = onSubmit
        textView.onPasteImages = onPasteImages

        if voiceOverFocusRequest != 0,
           voiceOverFocusRequest != context.coordinator.lastVoiceOverFocusRequest
        {
            context.coordinator.lastVoiceOverFocusRequest = voiceOverFocusRequest
            textView.requestVoiceOverFocus()
        }

        let newValue = telegramNSAttributedString(from: text)
        guard textView.attributedText != newValue else {
            if contextChanged {
                textView.selectedRange = NSRange(location: newValue.length, length: 0)
                context.coordinator.contextID = contextID
            }
            return
        }

        let selection = contextChanged
            ? NSRange(location: newValue.length, length: 0)
            : textView.selectedRange
        textView.attributedText = newValue
        textView.selectedRange = NSRange(
            location: min(selection.location, newValue.length),
            length: min(selection.length, max(0, newValue.length - selection.location)),
        )
        if newValue.length == 0 {
            textView.typingAttributes = defaultAttributes()
        }
        context.coordinator.contextID = contextID
    }
}

// MARK: - MessageTextEditor

struct MessageTextEditor: View {
    // MARK: Lifecycle

    init(
        _ placeholder: String = "",
        text: Binding<AttributedString>,
        contextID: AnyHashable = "composer",
        voiceOverFocusRequest: Int = 0,
        onSubmit: (() -> Void)? = nil,
        onPasteImages: (([SelectedImage]) -> Void)? = nil,
    ) {
        self.placeholder = placeholder
        self._text = text
        self.contextID = contextID
        self.voiceOverFocusRequest = voiceOverFocusRequest
        self.onSubmit = onSubmit
        self.onPasteImages = onPasteImages
    }

    // MARK: Internal

    var body: some View {
        sizingText
            .overlay(alignment: .topLeading) {
                if text.characters.isEmpty {
                    Text(placeholder)
                        .foregroundStyle(.gray)
                        .padding(.leading, 5)
                        .padding(.top, 8)
                        .accessibilityHidden(true)
                }
            }
            .overlay {
                MessageUITextViewRepresentable(
                    text: $text,
                    contextID: contextID,
                    voiceOverFocusRequest: voiceOverFocusRequest,
                    onSubmit: onSubmit,
                    onPasteImages: onPasteImages,
                )
                .accessibilityLabel(placeholder)
            }
            .frame(minHeight: 36)
            .fixedSize(horizontal: false, vertical: true)
            .clipped()
    }

    // MARK: Private

    @Binding private var text: AttributedString

    private let contextID: AnyHashable
    private let placeholder: String
    private let onSubmit: (() -> Void)?
    private let onPasteImages: (([SelectedImage]) -> Void)?
    private let voiceOverFocusRequest: Int

    private var sizingText: some View {
        Text(text.characters.isEmpty ? AttributedString(" ") : text)
            .font(.body)
            .lineLimit(10)
            .padding(.horizontal, 5)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .opacity(0)
            .accessibilityHidden(true)
    }
}
