// MessageTextPreview.swift

import SwiftUI

/// Chooses a preview using measured, wrapped text, including the action and timestamp. The
/// enclosing height proposal remains finite even inside a self-sizing table cell.
struct MessageTextPreview: View {
    let text: AttributedString
    let isShortened: Bool
    let trailingText: AttributedString?
    let maximumHeight: CGFloat
    let showFullText: () -> Void

    var body: some View {
        MessagePreviewHeightLayout(maximumHeight: maximumHeight) {
            ViewThatFits(in: .vertical) {
                if !isShortened {
                    Text(text + (trailingText ?? AttributedString()))
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach([12, 8, 4, 2, 1], id: \.self) { lineCount in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(text)
                            .lineLimit(lineCount)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button("Show more", action: showFullText)
                                .font(.footnote.weight(.semibold))
                            if let trailingText {
                                Spacer(minLength: 4)
                                Text(trailingText)
                            }
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
