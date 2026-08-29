// ConferenceVideoStageView.swift

import SwiftUI
import UIKit

// MARK: - ConferenceVideoStageView

struct ConferenceVideoStageView: View {
    let video: ConferenceVideoPresentation
    let isPinned: Bool
    let isUIHidden: Bool
    let collapse: () -> Void
    let togglePin: () -> Void
    let toggleUI: () -> Void
    let requestVideoView: (String, @escaping @MainActor (UIView?) -> Void) -> Void

    var body: some View {
        ZStack(alignment: .top) {
            Button(action: toggleUI) {
                ConferenceVideoTileView(
                    video: video,
                    showsOverlay: !isUIHidden,
                    requestVideoView: requestVideoView,
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(.plain)
            .accessibilityHint(isUIHidden ? "Shows call controls" : "Hides call controls")

            HStack {
                Button("Back to Video Grid", systemImage: "chevron.down", action: collapse)
                    .labelStyle(.iconOnly)

                Spacer()

                Button(
                    isPinned ? "Unpin" : "Pin",
                    systemImage: isPinned ? "pin.slash.fill" : "pin.fill",
                    action: togglePin,
                )
            }
            .font(.body.bold())
            .padding(10)
            .buttonStyle(.borderedProminent)
            .tint(.black.opacity(0.55))
            .opacity(isUIHidden ? 0 : 1)
            .allowsHitTesting(!isUIHidden)
            .accessibilityHidden(isUIHidden)
        }
    }
}
