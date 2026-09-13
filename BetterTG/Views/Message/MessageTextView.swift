// MessageTextView.swift

import SwiftUI
import TDLibKit

struct MessageTextView: View {
    // MARK: Internal

    let formattedText: FormattedText
    var trailingText: AttributedString?
    let showFullText: () -> Void

    var body: some View {
        let fullText = getAttributedString(from: formattedText)
        let shortenedText = truncatedMessageDisplayText(fullText)
        MessageTextPreview(
            text: shortenedText ?? fullText,
            isShortened: shortenedText != nil,
            trailingText: trailingText,
            maximumHeight: viewport.textPreviewHeight,
            showFullText: showFullText,
        )
    }

    // MARK: Private

    @Environment(ChatHistoryViewport.self) private var viewport
}
