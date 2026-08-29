// ConferenceLocalVideoStageView.swift

import SwiftUI
import UIKit

// MARK: - ConferenceLocalVideoStageView

struct ConferenceLocalVideoStageView: View {
    let videoView: UIView?
    let isScreenSharing: Bool
    let isPinned: Bool
    let collapse: () -> Void
    let togglePin: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            ConferenceLocalVideoTileView(
                videoView: videoView,
                isScreenSharing: isScreenSharing,
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
