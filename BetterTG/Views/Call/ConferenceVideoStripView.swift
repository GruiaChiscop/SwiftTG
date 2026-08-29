// ConferenceVideoStripView.swift

import SwiftUI
import UIKit

// MARK: - ConferenceVideoStripView

struct ConferenceVideoStripView: View {
    // MARK: Internal

    let localVideoView: UIView?
    let isLocalScreenSharing: Bool
    let videos: [ConferenceVideoPresentation]
    let isCompact: Bool
    let selectLocalVideo: () -> Void
    let selectVideo: (ConferenceVideoPresentation) -> Void
    let requestVideoView: (String, @escaping @MainActor (UIView?) -> Void) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 8) {
                if localVideoView != nil || isLocalScreenSharing {
                    Button(action: selectLocalVideo) {
                        ConferenceLocalVideoTileView(
                            videoView: localVideoView,
                            isScreenSharing: isLocalScreenSharing,
                        )
                    }
                    .buttonStyle(.plain)
                    .frame(width: localVideoWidth, height: tileHeight)
                }

                ForEach(videos) { video in
                    Button {
                        selectVideo(video)
                    } label: {
                        ConferenceVideoTileView(
                            video: video,
                            requestVideoView: requestVideoView,
                        )
                    }
                    .buttonStyle(.plain)
                    .frame(width: videoWidth(video), height: tileHeight)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
    }

    // MARK: Private

    private var localVideoWidth: CGFloat {
        if isCompact {
            return isLocalScreenSharing ? 136 : 88
        }
        return isLocalScreenSharing ? 260 : 168
    }

    private var tileHeight: CGFloat {
        isCompact ? 104 : 200
    }

    private func videoWidth(_ video: ConferenceVideoPresentation) -> CGFloat {
        if isCompact {
            return video.isScreenSharing ? 136 : 88
        }
        return video.isScreenSharing ? 260 : 168
    }
}
