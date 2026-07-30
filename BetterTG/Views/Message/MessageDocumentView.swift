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
                previewURL = friendlyNamedURL(for: file)
            } label: {
                Label(document.fileName, systemImage: "doc.fill")
                    .lineLimit(2)
                    .padding(10)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Document \(document.fileName)")
        } placeholder: {
            ProgressView("Downloading \(document.fileName)")
                .padding(10)
        }
        .quickLookPreview($previewURL)
    }

    // MARK: Private

    @State private var previewURL: URL?

    /// `.quickLookPreview` titles its preview (and any share sheet) from the URL's own file name -
    /// TDLib downloads store the file under its own internal name, not the sender's original file
    /// name, so previewing `file.local.path` directly shows that internal name instead of
    /// `document.fileName`. A symlink alongside it, named after the original file, fixes the title
    /// without copying the (possibly large) file contents.
    private func friendlyNamedURL(for file: File) -> URL {
        let sourceURL = URL(filePath: file.local.path)
        guard !document.fileName.isEmpty else { return sourceURL }
        let friendlyURL = FileManager.default.temporaryDirectory.appending(path: document.fileName)
        try? FileManager.default.removeItem(at: friendlyURL)
        do {
            try FileManager.default.createSymbolicLink(at: friendlyURL, withDestinationURL: sourceURL)
            return friendlyURL
        } catch {
            return sourceURL
        }
    }
}
