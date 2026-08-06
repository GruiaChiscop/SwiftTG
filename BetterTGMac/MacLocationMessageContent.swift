// MacLocationMessageContent.swift

import AppKit
import SwiftUI
import TDLibKit

struct MacLocationMessageContent: View {
    // MARK: Internal

    let presentation: TelegramLocationPresentation
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 0) {
                mapThumbnail
                    .frame(width: 240, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                HStack(spacing: 8) {
                    Image(systemName: presentation.isLive ? "location.fill.viewfinder" : "location.fill")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(presentation.title)
                        Text(presentation.subtitle ?? presentation.coordinateText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 8)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHidden(true)
        .task(id: presentation) {
            mapImage = await LocationMapSnapshot.image(
                latitude: presentation.location.latitude,
                longitude: presentation.location.longitude,
                size: CGSize(width: 240, height: 120),
                scale: NSScreen.main?.backingScaleFactor ?? 2,
            )
        }
    }

    // MARK: Private

    @State private var mapImage: NSImage?

    @ViewBuilder private var mapThumbnail: some View {
        if let mapImage {
            Image(nsImage: mapImage)
                .resizable()
                .scaledToFill()
                .frame(width: 240, height: 120)
        } else {
            Rectangle()
                .fill(.secondary.opacity(0.15))
                .overlay {
                    ProgressView()
                }
        }
    }
}
