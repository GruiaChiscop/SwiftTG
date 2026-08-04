// MessageContactView.swift

import SwiftUI
import TDLibKit

struct MessageContactView: View {
    let content: MessageContact
    let onTap: () -> Void

    var body: some View {
        let presentation = TelegramContactPresentation(content)
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(presentation.displayName)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    if !presentation.phoneNumber.isEmpty {
                        Text(presentation.phoneNumber)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
        }
        .buttonStyle(.plain)
    }
}
