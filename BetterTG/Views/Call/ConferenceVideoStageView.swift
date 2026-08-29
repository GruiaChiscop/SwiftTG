// ConferenceVideoStageView.swift

import SwiftUI
import UIKit

// MARK: - ConferenceVideoStageView

struct ConferenceVideoStageView: View {
    let video: ConferenceVideoPresentation
    let isPinned: Bool
    let collapse: () -> Void
    let togglePin: () -> Void
    let requestVideoView: (String, @escaping @MainActor (UIView?) -> Void) -> Void

    var body: some View {
        ZStack(alignment: .top) {
            ConferenceVideoTileView(
                video: video,
                requestVideoView: requestVideoView,
            )

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
        }
    }
}
