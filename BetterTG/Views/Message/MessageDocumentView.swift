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
                preparePreview(for: file)
            } label: {
                HStack {
                    Label(document.fileName, systemImage: "doc.fill")
                        .lineLimit(2)
                    if isPreparingPreview {
                        ProgressView()
                    }
                }
                .padding(10)
            }
            .buttonStyle(.plain)
            .disabled(isPreparingPreview)
            .accessibilityLabel("Document \(document.fileName)")
        } placeholder: {
            ProgressView("Downloading \(document.fileName)")
                .padding(10)
        }
        .quickLookPreview($previewURL)
        .alert("Document couldn't be previewed", isPresented: previewErrorIsPresented) {
            Button("OK") {}
        } message: {
            Text(previewError ?? "")
        }
    }

    // MARK: Private

    @State private var previewURL: URL?
    @State private var isPreparingPreview = false
    @State private var previewError: String?

    private var previewErrorIsPresented: Binding<Bool> {
        Binding(
            get: { previewError != nil },
            set: { isPresented in
                if !isPresented {
                    previewError = nil
                }
            },
        )
    }

    private func preparePreview(for file: File) {
        guard !isPreparingPreview else { return }
        isPreparingPreview = true
        previewError = nil
        Task { @MainActor in
            defer { isPreparingPreview = false }
            do {
                previewURL = try await TelegramDocumentExport.previewURL(
                    sourceURL: URL(filePath: file.local.path),
                    suggestedFileName: document.fileName,
                    mimeType: document.mimeType,
                    identifier: String(file.id),
                )
            } catch {
                guard !Task.isCancelled else { return }
                previewError = telegramErrorDescription(error)
            }
        }
    }
}
