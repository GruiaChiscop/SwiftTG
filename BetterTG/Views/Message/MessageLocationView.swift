// MessageLocationView.swift

import SwiftUI
import TDLibKit

struct MessageLocationView: View {
    // MARK: Internal

    let presentation: TelegramLocationPresentation
    let messageId: Int64
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
            .accessibilityLabel(presentation.contentDescription)

            if let activeShare {
                HStack {
                    Group {
                        if activeShare.isIndefinite {
                            Text("Sharing until you stop")
                        } else {
                            Text(activeShare.expiresAt, style: .timer)
                                .monospacedDigit()
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Spacer()

                    Button("Stop Sharing") {
                        Task { await liveManager.stop(messageId: messageId) }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
                    .accessibilityLabel("Stop sharing live location")
                }
                .padding(.horizontal, 4)
            }
        }
        .frame(maxWidth: 260)
        .accessibilityElement(children: .contain)
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
    @State private var liveManager = TelegramLiveLocationManager.shared

    /// Non-nil only for this device's own live-location message while it's still being updated -
    /// `activeShares` never holds anyone else's share or an expired one.
    private var activeShare: TelegramLiveShare? {
        guard presentation.isLive else { return nil }
        return liveManager.activeShares[messageId]
    }

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
