// MessageTextView.swift

import SwiftUI
import TDLibKit

struct MessageTextView: View {
    // MARK: Lifecycle

    init(formattedText: FormattedText, trailingText: AttributedString? = nil) {
        self.formattedText = formattedText
        self.trailingText = trailingText
    }

    // MARK: Internal

    let formattedText: FormattedText
    let trailingText: AttributedString?

    var body: some View {
        Text(displayedText)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Private

    private var displayedText: AttributedString {
        var result = getAttributedString(from: formattedText)
        if let trailingText {
            result.append(trailingText)
        }
        return result
    }
}
