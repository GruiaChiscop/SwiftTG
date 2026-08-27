// ConferenceLocalVideoTileView.swift

import SwiftUI
import UIKit

// MARK: - ConferenceLocalVideoTileView

struct ConferenceLocalVideoTileView: View {
    let videoView: UIView
    let isScreenSharing: Bool

    var body: some View {
        CallVideoSurfaceView(videoView: videoView)
            .id(ObjectIdentifier(videoView))
            .clipShape(.rect(cornerRadius: 16))
            .overlay(alignment: .bottomLeading) {
                Text(isScreenSharing ? "Your Screen" : "You")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.55), in: .capsule)
                    .padding(8)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(isScreenSharing ? "Your screen sharing" : "You, camera")
    }
}
