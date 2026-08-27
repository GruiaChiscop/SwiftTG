// ConferenceLocalVideoTileView.swift

import SwiftUI
import UIKit

// MARK: - ConferenceLocalVideoTileView

struct ConferenceLocalVideoTileView: View {
    let videoView: UIView

    var body: some View {
        CallVideoSurfaceView(videoView: videoView)
            .id(ObjectIdentifier(videoView))
            .aspectRatio(3 / 4, contentMode: .fill)
            .clipShape(.rect(cornerRadius: 16))
            .overlay(alignment: .bottomLeading) {
                Text("You")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.55), in: .capsule)
                    .padding(8)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("You, camera")
    }
}
