// UnreadMessagesHeader.swift

import SwiftUI

// MARK: - UnreadMessagesHeader

struct UnreadMessagesHeader: View {
    // MARK: Internal

    let count: Int

    var body: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(.blue.opacity(0.6))
                .frame(height: 1)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.blue)
                .fixedSize()
            Rectangle()
                .fill(.blue.opacity(0.6))
                .frame(height: 1)
        }
        .padding(.vertical, 6)
        .accessibilityHidden(true)
    }

    // MARK: Private

    private var title: String {
        "\(count) unread \(count == 1 ? "message" : "messages")"
    }
}
