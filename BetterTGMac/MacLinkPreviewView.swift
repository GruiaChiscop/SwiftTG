// MacLinkPreviewView.swift

import AppKit
import SwiftUI
import TDLibKit

struct MacLinkPreviewView: View {
    // MARK: Internal

    @Bindable var model: MacSessionModel

    let preview: LinkPreview

    var body: some View {
        Group {
            if let destination = presentation.url {
                Link(destination: destination) {
                    previewCard
                }
                .buttonStyle(.plain)
            } else {
                previewCard
            }
        }
        .frame(maxWidth: 360, alignment: .leading)
        .task(id: presentation.media?.fileId) {
            guard let fileId = presentation.media?.fileId,
                  let path = await model.localPhotoPath(fileId: fileId)
            else {
                image = nil
                return
            }
            image = await Self.decodedImage(atPath: path)
        }
    }

    // MARK: Private

    @State private var image: NSImage?

    private var presentation: TelegramLinkPreviewPresentation {
        TelegramLinkPreviewPresentation(preview)
    }

    private var previewCard: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(.tint)
                .frame(width: 3)

            if let media = presentation.media, !presentation.showLargeMedia {
                previewText
                    .frame(maxWidth: .infinity, alignment: .leading)
                previewImage(media, isLarge: false)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    if let media = presentation.media, presentation.showMediaAboveDescription {
                        previewImage(media, isLarge: true)
                    }
                    previewText
                    if let media = presentation.media, !presentation.showMediaAboveDescription {
                        previewImage(media, isLarge: true)
                    }
                }
            }
        }
        .padding(8)
        .background(.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .contentShape(.rect)
    }

    private var previewText: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(presentation.siteName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)
                .lineLimit(1)
            if !presentation.title.isEmpty {
                Text(presentation.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }
            if !presentation.author.isEmpty {
                Text(presentation.author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if !presentation.summary.isEmpty {
                Text(presentation.summary)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
            }
        }
    }

    private func previewImage(_ media: TelegramLinkPreviewMedia, isLarge: Bool) -> some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if let data = media.minithumbnailData, let thumbnail = NSImage(data: data) {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: 4)
            } else {
                Rectangle()
                    .fill(.secondary.opacity(0.15))
                    .overlay {
                        Image(systemName: "link")
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(
            width: isLarge ? nil : 72,
            height: isLarge ? largeMediaHeight(for: media) : 72,
        )
        .frame(maxWidth: isLarge ? .infinity : nil)
        .clipShape(.rect(cornerRadius: 6))
    }

    private static func decodedImage(atPath path: String) async -> NSImage? {
        await Task.detached(priority: .userInitiated) {
            NSImage(contentsOfFile: path)
        }.value
    }

    private func largeMediaHeight(for media: TelegramLinkPreviewMedia) -> CGFloat {
        let aspectRatio = media.aspectRatio ?? 16 / 9
        return min(220, max(120, 320 / aspectRatio))
    }
}
