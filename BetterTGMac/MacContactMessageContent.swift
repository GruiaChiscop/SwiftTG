// MacContactMessageContent.swift

import SwiftUI
import TDLibKit

struct MacContactMessageContent: View {
    let content: MessageContact
    let onOpen: () -> Void

    var body: some View {
        let presentation = TelegramContactPresentation(content)
        Button(action: onOpen) {
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle.fill")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(presentation.displayName)
                    if !presentation.phoneNumber.isEmpty {
                        Text(presentation.phoneNumber)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHidden(true)
    }
}
