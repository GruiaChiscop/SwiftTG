// MessageTextView.swift

import SwiftUI
import TDLibKit

struct MessageTextView: View {
    let formattedText: FormattedText

    var body: some View {
        Text(getAttributedString(from: formattedText, withDate: true))
            .fixedSize(horizontal: false, vertical: true)
    }
}
