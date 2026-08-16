// CallEncryptionKeyView.swift

import SwiftUI

// MARK: - CallEncryptionKeyView

struct CallEncryptionKeyView: View {
    // MARK: Internal

    let emojis: [String]
    let peerName: String

    var body: some View {
        Button(action: showEncryptionInfo) {
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
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showsEncryptionInfo, arrowEdge: .top) {
            CallEncryptionInfoView(peerName: peerName, dismiss: dismissEncryptionInfo)
                .presentationCompactAdaptation(.popover)
        }
    }

    // MARK: Private

    @State private var showsEncryptionInfo = false

    private func showEncryptionInfo() {
        showsEncryptionInfo = true
    }

    private func dismissEncryptionInfo() {
        showsEncryptionInfo = false
    }
}

// MARK: - CallEncryptionInfoView

private struct CallEncryptionInfoView: View {
    let peerName: String
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("This call is end-to-end encrypted")
                .font(.headline)

            Text("If the emoji on \(peerName)'s screen are the same, this call is 100% secure.")
                .foregroundStyle(.secondary)

            Divider()

            Button("OK", action: dismiss)
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .multilineTextAlignment(.center)
        .padding()
        .frame(idealWidth: 320)
    }
}
