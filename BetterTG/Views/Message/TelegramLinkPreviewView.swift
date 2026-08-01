// TelegramLinkPreviewView.swift

import SwiftUI
import TDLibKit

struct TelegramLinkPreviewView: View {
    // MARK: Internal

    let preview: LinkPreview
    let service: any TelegramService

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
        .frame(maxWidth: 320, alignment: .leading)
    }

    // MARK: Private

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
        .background(.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
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
        AsyncTdImage(id: media.fileId, maxPixelSize: isLarge ? 800 : 180, service: service) { image, _ in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
        } placeholder: {
            Group {
                if let image = Image(data: media.minithumbnailData) {
                    image
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
        }
        .frame(
            width: isLarge ? nil : 72,
            height: isLarge ? largeMediaHeight(for: media) : 72,
        )
        .frame(maxWidth: isLarge ? .infinity : nil)
        .clipShape(.rect(cornerRadius: 8))
    }

    private func largeMediaHeight(for media: TelegramLinkPreviewMedia) -> CGFloat {
        let aspectRatio = media.aspectRatio ?? 16 / 9
        return min(220, max(120, 280 / aspectRatio))
    }
}
