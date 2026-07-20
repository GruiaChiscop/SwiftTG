// MacAttachmentPreview.swift

import AppKit
import SwiftUI

/// Full review step shown after picking photos or files, before sending - mirrors iOS's
/// `AttachmentPreviewView`, adapted to this codebase's macOS sheet convention (manual header +
/// Close button, fixed frame, per `MacPhotoPreview`) since SwiftUI's paged `TabView(.page)` isn't
/// available on macOS; a click-to-select filmstrip stands in for paging when there's more than
/// one item.
struct MacAttachmentPreview: View {
    // MARK: Internal

    @Bindable var model: MacSessionModel

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(itemCount > 1 ? "\(itemCount) Items" : (isPhotos ? "Photo" : "Document"))
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if itemCount > 1 {
                    Button("Remove", systemImage: "trash", role: .destructive, action: removeSelectedItem)
                        .labelStyle(.iconOnly)
                }
                Button("Cancel", systemImage: "xmark") { cancel() }
                    .labelStyle(.iconOnly)
                    .keyboardShortcut(.cancelAction)
            }

            mainPreview
                .frame(minWidth: 480, minHeight: 280)

            if itemCount > 1 {
                filmstrip
            }

            HStack(alignment: .bottom, spacing: 10) {
                MacComposerTextField(
                    text: $model.messageText,
                    accessibilityLabel: "Caption",
                    onPasteFiles: { _ in false },
                    onSubmit: send,
                )
                .frame(minHeight: 32, idealHeight: 48, maxHeight: 96)

                Button("Send", systemImage: "paperplane.fill", action: send)
                    .labelStyle(.iconOnly)
                    .keyboardShortcut(.return, modifiers: [.command])
            }
        }
        .padding(16)
        .frame(minWidth: 600, minHeight: 480)
        .onChange(of: itemCount) { _, newValue in
            selectedIndex = min(selectedIndex, max(0, newValue - 1))
        }
    }

    // MARK: Private

    @State private var selectedIndex = 0

    private var isPhotos: Bool { !model.selectedPhotoURLs.isEmpty }
    private var currentURLs: [URL] { isPhotos ? model.selectedPhotoURLs : model.selectedDocumentURLs }
    private var itemCount: Int { model.selectedPhotoURLs.count + model.selectedDocumentURLs.count }

    @ViewBuilder private var mainPreview: some View {
        if currentURLs.indices.contains(selectedIndex) {
            let url = currentURLs[selectedIndex]
            if isPhotos, let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel("Photo \(selectedIndex + 1) of \(currentURLs.count)")
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(.secondary)
                    Text(url.lastPathComponent)
                        .font(.headline)
                        .lineLimit(3)
                        .multilineTextAlignment(.center)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Document \(selectedIndex + 1) of \(currentURLs.count): \(url.lastPathComponent)")
            }
        }
    }

    private var filmstrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Array(currentURLs.enumerated()), id: \.offset) { index, url in
                    thumbnail(for: url)
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(index == selectedIndex ? Color.accentColor : .clear, lineWidth: 2)
                        }
                        .onTapGesture { selectedIndex = index }
                        .accessibilityLabel("Item \(index + 1) of \(currentURLs.count)")
                        .accessibilityAddTraits(index == selectedIndex ? [.isSelected] : [])
                }
            }
        }
    }

    private func thumbnail(for url: URL) -> some View {
        Group {
            if isPhotos, let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "doc.fill")
            }
        }
    }

    private func send() {
        model.submitComposer()
    }

    private func cancel() {
        model.selectedPhotoURLs.removeAll()
        model.selectedDocumentURLs.removeAll()
    }

    private func removeSelectedItem() {
        guard currentURLs.indices.contains(selectedIndex) else { return }
        if isPhotos {
            model.removeSelectedPhoto(currentURLs[selectedIndex])
        } else {
            model.removeSelectedDocument(currentURLs[selectedIndex])
        }
    }
}
