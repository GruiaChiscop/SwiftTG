// MessageDocumentView.swift

import QuickLook
import SwiftUI
import TDLibKit

struct MessageDocumentView: View {
    // MARK: Internal

    let document: Document
    let service: any TelegramService
    let downloadIsPaused: Bool
    let onDownloadToggle: () -> Void
    var onTransferStatusChange: (String?) -> Void = { _ in }

    var body: some View {
        AsyncTdFile(
            id: document.document.id,
            service: service,
            isPaused: downloadIsPaused,
        ) { file in
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
            let status = downloadIsPaused
                ? "Download paused, \(document.fileName)"
                : TelegramFileTransferProgress.downloadStatus(
                    fileName: document.fileName,
                    file: file,
                )
            Button(action: onDownloadToggle) {
                HStack(spacing: 10) {
                    if downloadIsPaused {
                        Image(systemName: "arrow.down.circle")
                            .frame(width: 28, height: 28)
                    } else if let progress = TelegramFileTransferProgress.fraction(file) {
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
                        Text(downloadIsPaused
                            ? "Download paused"
                            : TelegramFileTransferProgress.downloadLabel(file: file))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(10)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(status)
            .modify {
                if downloadIsPaused {
                    $0
                } else {
                    $0.accessibilityAddTraits(.updatesFrequently)
                }
            }
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
