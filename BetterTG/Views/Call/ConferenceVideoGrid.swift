// ConferenceVideoGrid.swift

import SwiftUI
import UIKit

// MARK: - ConferenceVideoGrid

struct ConferenceVideoGrid: View {
    let videos: [ConferenceVideoPresentation]
    let requestVideoView: (String, @escaping @MainActor (UIView?) -> Void) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 8) {
                ForEach(videos) { video in
                    ConferenceVideoTileView(
                        video: video,
                        requestVideoView: requestVideoView,
                    )
                    .frame(width: video.isScreenSharing ? 260 : 168, height: 200)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
    }
}
