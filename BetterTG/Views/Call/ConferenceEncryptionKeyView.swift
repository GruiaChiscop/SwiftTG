// ConferenceEncryptionKeyView.swift

import SwiftUI

// MARK: - ConferenceEncryptionKeyView

/// Telegram-iOS places this expandable key directly below the conference title. TDLib changes the
/// four emoji whenever conference membership changes, allowing every participant to compare the
/// same end-to-end encryption fingerprint.
struct ConferenceEncryptionKeyView: View {
    // MARK: Internal

    let emojis: [String]

    var body: some View {
        Button(action: toggleExpanded) {
            Group {
                if isExpanded {
                    expandedContent
                } else {
                    collapsedContent
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : .spring(duration: 0.4), value: isExpanded)
    }

    // MARK: Private

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false

    private var displayedEmojis: [String] {
        Array(emojis.prefix(4))
    }

    private var leadingEmojis: String {
        if displayedEmojis.isEmpty {
            return "••"
        }
        return displayedEmojis.prefix(2).joined()
    }

    private var trailingEmojis: String {
        if displayedEmojis.isEmpty {
            return "••"
        }
        return displayedEmojis.dropFirst(2).joined()
    }

    private var expandedEmojiText: String {
        displayedEmojis.isEmpty ? "••••" : displayedEmojis.joined(separator: " ")
    }

    private var collapsedContent: some View {
        HStack(spacing: 5) {
            Text(leadingEmojis)
                .font(.title2)
                .accessibilityHidden(displayedEmojis.isEmpty)
            Text("End-to-end encrypted")
                .font(.caption.bold())
            Text(trailingEmojis)
                .font(.title2)
                .accessibilityHidden(displayedEmojis.isEmpty)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: .capsule)
    }

    private var expandedContent: some View {
        VStack(spacing: 10) {
            Text(expandedEmojiText)
                .font(.largeTitle)
                .accessibilityHidden(displayedEmojis.isEmpty)

            Text(
                "These four emojis represent the call's encryption key. They must match for all "
                    + "participants and change when someone joins or leaves.",
            )
            .font(.caption)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            Divider()

            Text("Close")
                .font(.body)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 400)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 26))
    }

    private func toggleExpanded() {
        isExpanded.toggle()
    }
}
