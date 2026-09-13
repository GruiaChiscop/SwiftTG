// FullMessageTextView.swift

import SwiftUI
import TDLibKit

struct FullMessageTextView: View {
    // MARK: Internal

    let formattedText: FormattedText

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(getAttributedString(from: formattedText, .primary))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle("Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
}
