// MessageLocationView.swift

import SwiftUI
import TDLibKit

struct MessageLocationView: View {
    // MARK: Internal

    let presentation: TelegramLocationPresentation
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                mapThumbnail
                    .frame(height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)
                HStack(spacing: 10) {
                    Image(systemName: presentation.isLive ? "location.fill.viewfinder" : "location.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(presentation.title)
                            .foregroundStyle(.primary)
                        Text(presentation.subtitle ?? presentation.coordinateText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(10)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: 260)
        .accessibilityLabel(presentation.contentDescription)
        .task(id: presentation) {
            mapImage = await LocationMapSnapshot.image(
                latitude: presentation.location.latitude,
                longitude: presentation.location.longitude,
                size: CGSize(width: 260, height: 120),
                scale: displayScale,
            )
        }
    }

    // MARK: Private

    @Environment(\.displayScale) private var displayScale
    @State private var mapImage: UIImage?

    @ViewBuilder private var mapThumbnail: some View {
        if let mapImage {
            Image(uiImage: mapImage)
                .resizable()
                .scaledToFill()
                .frame(width: 260, height: 120)
        } else {
            Rectangle()
                .fill(.secondary.opacity(0.15))
                .overlay {
                    ProgressView()
                }
        }
    }
}
