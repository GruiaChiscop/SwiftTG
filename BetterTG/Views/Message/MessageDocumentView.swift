// MessageDocumentView.swift

import QuickLook
import SwiftUI
import TDLibKit
import UIKit

struct MessageDocumentView: View {
    // MARK: Internal

    let document: Document
    var onTransferStatusChange: (String?) -> Void = { _ in }

    var body: some View {
        AsyncTdFile(id: document.document.id) { file in
            Button {
                preparePreview(for: file)
            } label: {
                HStack(spacing: 10) {
                    if isPreparingPreview {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .frame(width: 28, height: 28)
                    } else {
                        Image(systemName: "doc.fill")
                            .frame(width: 28, height: 28)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(document.fileName)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        if isPreparingPreview {
                            Text("Preparing preview…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(10)
            }
            .buttonStyle(.plain)
            .disabled(isPreparingPreview)
            .accessibilityLabel("Document \(document.fileName)")
            .accessibilityValue(isPreparingPreview ? "Preparing preview" : "")
            .onAppear {
                if !isPreparingPreview {
                    onTransferStatusChange(nil)
                }
            }
        } placeholder: { file in
            let status = TelegramFileTransferProgress.downloadStatus(
                fileName: document.fileName,
                file: file,
            )
            HStack(spacing: 10) {
                if let progress = TelegramFileTransferProgress.fraction(file) {
                    ProgressView(value: progress)
                        .progressViewStyle(.circular)
                        .frame(width: 28, height: 28)
                } else {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .frame(width: 28, height: 28)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(document.fileName)
                        .lineLimit(2)
                    Text(TelegramFileTransferProgress.downloadLabel(file: file))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(status)
            .accessibilityAddTraits(.updatesFrequently)
            .onAppear { onTransferStatusChange(status) }
            .onChange(of: status) { _, newStatus in
                onTransferStatusChange(newStatus)
            }
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
        onTransferStatusChange("Preparing preview for \(document.fileName)")
        UIAccessibility.post(
            notification: .announcement,
            argument: "Preparing preview for \(document.fileName)",
        )
        Task { @MainActor in
            defer {
                isPreparingPreview = false
                onTransferStatusChange(nil)
            }
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
