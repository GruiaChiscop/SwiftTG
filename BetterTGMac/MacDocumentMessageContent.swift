// MacDocumentMessageContent.swift

import SwiftUI
import TDLibKit

struct MacDocumentMessageContent: View {
    let content: MessageDocument
    let isDownloaded: Bool
    let isLoading: Bool
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: onOpen) {
                HStack(spacing: 8) {
                    Image(systemName: "doc.fill")
                    Text(content.document.fileName)
                        .lineLimit(2)
                    if isLoading {
                        ProgressView()
                    } else if !isDownloaded {
                        Image(systemName: "arrow.down.circle")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
            .accessibilityHidden(true)
            if !content.caption.text.isEmpty {
                MacFormattedTextView(formattedText: content.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
