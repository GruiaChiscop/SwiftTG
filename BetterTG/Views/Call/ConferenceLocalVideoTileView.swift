// ConferenceLocalVideoTileView.swift

import SwiftUI
import UIKit

// MARK: - ConferenceLocalVideoTileView

struct ConferenceLocalVideoTileView: View {
    let videoView: UIView?
    let isScreenSharing: Bool

    var body: some View {
        if isScreenSharing {
            ZStack {
                Color.white.opacity(0.08)
                VStack(spacing: 10) {
                    Image(systemName: "rectangle.on.rectangle")
                        .font(.title)
                        .accessibilityHidden(true)
                    Text("You are sharing your screen")
                        .font(.caption.bold())
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
            .clipShape(.rect(cornerRadius: 16))
        } else if let videoView {
            CallVideoSurfaceView(videoView: videoView)
                .id(ObjectIdentifier(videoView))
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
}
