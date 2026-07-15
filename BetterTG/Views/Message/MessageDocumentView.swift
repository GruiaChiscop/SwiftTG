// MessageDocumentView.swift

import QuickLook
import SwiftUI
import TDLibKit

struct MessageDocumentView: View {
    // MARK: Internal

    let document: Document

    var body: some View {
        AsyncTdFile(id: document.document.id) { file in
            Button {
                previewURL = URL(filePath: file.local.path)
            } label: {
                Label(document.fileName, systemImage: "doc.fill")
                    .lineLimit(2)
                    .padding(10)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Document \(document.fileName)")
            .accessibilityHint("Double tap to open")
        } placeholder: {
            ProgressView("Downloading \(document.fileName)")
                .padding(10)
        }
        .quickLookPreview($previewURL)
    }

    // MARK: Private

    @State private var previewURL: URL?
}
