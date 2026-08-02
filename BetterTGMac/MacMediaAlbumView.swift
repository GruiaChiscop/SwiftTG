// MacMediaAlbumView.swift

import AppKit
import SwiftUI
import TDLibKit

// MARK: - MacMediaAlbumView

struct MacMediaAlbumView: View {
    // MARK: Internal

    let model: MacSessionModel
    let messages: [Message]
    let onOpen: (Message) -> Void

    var body: some View {
        LazyVGrid(columns: columns, spacing: spacing) {
            ForEach(messages) { message in
                MacMediaAlbumItemView(model: model, message: message) {
                    onOpen(message)
                }
                .frame(width: itemSide, height: itemSide)
            }
        }
        .frame(width: albumWidth, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .accessibilityHidden(true)
    }

    // MARK: Private

    private let spacing: CGFloat = 2

    private var columnCount: Int {
        if messages.count <= 1 {
            1
        } else if messages.count <= 4 {
            2
        } else {
            3
        }
    }

    private var albumWidth: CGFloat {
        messages.count <= 1 ? 320 : 360
    }

    private var itemSide: CGFloat {
        (albumWidth - spacing * CGFloat(columnCount - 1)) / CGFloat(columnCount)
    }

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.fixed(itemSide), spacing: spacing),
            count: columnCount,
        )
    }
}

// MARK: - MacMediaAlbumItemView

private struct MacMediaAlbumItemView: View {
    // MARK: Internal

    let model: MacSessionModel
    let message: Message
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            ZStack {
                Color.secondary.opacity(0.12)

                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    ProgressView()
                }

                if case .messageVideo(let content) = message.content {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 38))
                        .foregroundStyle(.white)
                        .shadow(radius: 3)

                    Text(telegramClockDuration(content.video.duration))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.7), in: Capsule())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(7)
                }
            }
            .contentShape(.rect)
            .clipped()
        }
        .buttonStyle(.plain)
        .task(id: presentationTaskID) {
            guard let fileId else {
                image = nil
                return
            }
            guard let path = await model.localPhotoPath(fileId: fileId) else {
                image = nil
                return
            }
            image = await Self.decodedImage(atPath: path)
        }
    }

    // MARK: Private

    @State private var image: NSImage?

    private var presentationTaskID: String {
        "\(message.id):\(message.editDate)"
    }

    private var fileId: Int? {
        switch message.content {
        case .messagePhoto(let content):
            return content.photo
                .sizes
                .max {
                    $0.width * $0.height < $1.width * $1.height
                }?.photo
                .id
        case .messageVideo(let content):
            if let cover = content.cover {
                return cover.sizes
                    .max {
                        $0.width * $0.height < $1.width * $1.height
                    }?.photo
                    .id
            }
            return content.video.thumbnail?.file.id
        default:
            return nil
        }
    }

    private static func decodedImage(atPath path: String) async -> NSImage? {
        await Task.detached(priority: .userInitiated) {
            NSImage(contentsOfFile: path)
        }.value
    }
}

// MARK: - MacAlbumMediaPreview

struct MacAlbumMediaPreview: View {
    // MARK: Internal

    let model: MacSessionModel
    let message: Message

    var body: some View {
        switch message.content {
        case .messagePhoto(let content):
            photoPreview(content)
                .task(id: message.id) { await loadPhoto() }
        case .messageVideo(let content):
            MacVideoPreview(
                model: model,
                fileId: content.video.video.id,
                caption: content.caption.text,
                duration: content.video.duration,
                startTimestamp: content.startTimestamp,
            )
        default:
            ContentUnavailableView("Media Unavailable", systemImage: "exclamationmark.triangle")
                .frame(minWidth: 480, minHeight: 320)
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var image: NSImage?
    @State private var fileURL: URL?
    @State private var didFail = false

    private func photoPreview(_ content: MessagePhoto) -> some View {
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

            Group {
                if let image {
                    ScrollView([.horizontal, .vertical]) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(minWidth: 320, minHeight: 240)
                            .accessibilityLabel(
                                content.caption.text.isEmpty ? "Photo" : "Photo: \(content.caption.text)",
                            )
                    }
                } else if didFail {
                    ContentUnavailableView(
                        "Photo Unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text("The photo could not be downloaded."),
                    )
                } else {
                    ProgressView("Downloading photo…")
                        .accessibilityAddTraits(.updatesFrequently)
                }
            }
            .frame(minWidth: 560, minHeight: 360)

            if !content.caption.text.isEmpty {
                Text(content.caption.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }

            if let fileURL {
                HStack {
                    Spacer()
                    Button("Open in Default App", systemImage: "arrow.up.forward.app") {
                        NSWorkspace.shared.open(fileURL)
                    }
                }
            }
        }
        .padding(16)
        .frame(minWidth: 600, minHeight: 480)
    }

    private func loadPhoto() async {
        guard case .messagePhoto(let content) = message.content,
              let fileId = content.photo
                  .sizes
                  .max(by: {
                      $0.width * $0.height < $1.width * $1.height
                  })?.photo
                  .id,
                  let path = await model.localPhotoPath(fileId: fileId)
        else {
            didFail = true
            return
        }
        let image = await Task.detached(priority: .userInitiated) {
            NSImage(contentsOfFile: path)
        }.value
        guard let image else {
            didFail = true
            return
        }
        self.image = image
        fileURL = URL(filePath: path)
    }
}
