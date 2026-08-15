// CallEncryptionKeyView.swift

import SwiftUI

// MARK: - CallEncryptionKeyView

struct CallEncryptionKeyView: View {
    let emojis: [String]

    var body: some View {
        VStack(spacing: 6) {
            Text(emojis.joined(separator: " "))
                .font(.title2)
            Text("Encryption Key")
                .font(.footnote.bold())
            Text("Compare with the other person")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding()
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }
}
