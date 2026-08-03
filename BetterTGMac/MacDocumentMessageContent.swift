// MacDocumentMessageContent.swift

import SwiftUI
import TDLibKit

struct MacDocumentMessageContent: View {
    let content: MessageDocument
    let isDownloaded: Bool
    let isLoading: Bool
    let isPaused: Bool
    let interactionIsDisabled: Bool
    let transferProgress: Double?
    let transferStatus: String?
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: onOpen) {
                HStack(spacing: 8) {
                    if isPaused {
                        Image(systemName: "arrow.down.circle")
                    } else if isLoading {
                        if let transferProgress {
                            ProgressView(value: transferProgress)
                                .progressViewStyle(.circular)
                        } else {
                            ProgressView()
                                .progressViewStyle(.circular)
                        }
                    } else {
                        Image(systemName: "doc.fill")
                    }
                    Text(content.document.fileName)
                        .lineLimit(2)
                    if !isPaused, !isLoading, !isDownloaded {
                        Image(systemName: "arrow.down.circle")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(interactionIsDisabled)
            .accessibilityHidden(true)
            if let transferStatus {
                Text(transferStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            if !content.caption.text.isEmpty {
                MacFormattedTextView(formattedText: content.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
