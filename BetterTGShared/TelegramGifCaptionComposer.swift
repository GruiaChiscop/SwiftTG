// TelegramGifCaptionComposer.swift

import SwiftUI

// MARK: - TelegramGifCaptionComposer

struct TelegramGifCaptionComposer<Preview: View>: View {
    // MARK: Lifecycle

    init(
        onSend: @escaping @MainActor (String) async throws -> Void,
        @ViewBuilder preview: () -> Preview,
    ) {
        self.onSend = onSend
        self.preview = preview()
    }

    // MARK: Internal

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Caption")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            preview
                .frame(maxWidth: 280, maxHeight: 220)
                .clipShape(.rect(cornerRadius: 12))
                .accessibilityHidden(true)

            TextField("Add a caption…", text: $caption, axis: .vertical)
                .lineLimit(2...5)

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .accessibilityFocused($errorIsFocused)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isSending)
                Button("Send", systemImage: "paperplane.fill", action: send)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isSending)
            }
        }
        .padding()
        .frame(maxWidth: 440)
        .interactiveDismissDisabled(isSending)
    }

    // MARK: Private

    @AccessibilityFocusState private var errorIsFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var caption = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    private let onSend: @MainActor (String) async throws -> Void
    private let preview: Preview

    private func send() {
        guard !isSending else { return }
        isSending = true
        errorMessage = nil
        errorIsFocused = false
        Task {
            do {
                try await onSend(caption)
                dismiss()
            } catch {
                errorMessage = telegramErrorDescription(error)
                isSending = false
                await Task.yield()
                errorIsFocused = true
            }
        }
    }
}
