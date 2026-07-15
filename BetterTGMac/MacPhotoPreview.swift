// MacPhotoPreview.swift

import AppKit
import SwiftUI

struct MacPhotoPreview: View {
    // MARK: Internal

    let image: NSImage
    let caption: String
    let fileURL: URL

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Photo")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Close", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
                    .keyboardShortcut(.cancelAction)
            }

            ScrollView([.horizontal, .vertical]) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(minWidth: 320, minHeight: 240)
                    .accessibilityLabel(caption.isEmpty ? "Photo" : "Photo: \(caption)")
            }

            if !caption.isEmpty {
                Text(caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }

            HStack {
                Spacer()
                Button("Open in Default App", systemImage: "arrow.up.forward.app") {
                    NSWorkspace.shared.open(fileURL)
                }
            }
        }
        .padding(16)
        .frame(minWidth: 600, minHeight: 480)
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
}
