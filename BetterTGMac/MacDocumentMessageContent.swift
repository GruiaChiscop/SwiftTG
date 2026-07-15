// MacDocumentMessageContent.swift

import SwiftUI
import TDLibKit

struct MacDocumentMessageContent: View {
    let content: MessageDocument
    let isDownloaded: Bool
    let isLoading: Bool
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 8) {
                Image(systemName: "doc.fill")
                VStack(alignment: .leading, spacing: 2) {
                    Text(content.document.fileName)
                        .lineLimit(2)
                    if !content.caption.text.isEmpty {
                        Text(content.caption.text)
                            .foregroundStyle(.secondary)
                    }
                }
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
    }
}
