// ConferenceVideoStripView.swift

import SwiftUI
import UIKit

// MARK: - ConferenceVideoStripView

struct ConferenceVideoStripView: View {
    // MARK: Internal

    let localVideoView: UIView?
    let isLocalScreenSharing: Bool
    let videos: [ConferenceVideoPresentation]
    let participants: [ConferenceParticipantPresentation]
    let performingParticipantActionId: String?
    let isCompact: Bool
    let selectLocalVideo: () -> Void
    let selectVideo: (ConferenceVideoPresentation) -> Void
    let setParticipantMuted: (ConferenceParticipantPresentation, ConferenceParticipantMuteAction) -> Void
    let setParticipantVolume: (ConferenceParticipantPresentation, Int, Bool) -> Void
    let openParticipantConversation: (ConferenceParticipantPresentation) -> Void
    let removeParticipant: (ConferenceParticipantPresentation) -> Void
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
                    if let participant = participant(for: video) {
                        ConferenceVideoParticipantTile(
                            video: video,
                            participant: participant,
                            isPerformingAction: performingParticipantActionId == participant.id,
                            select: selectVideo,
                            setMuted: { action in
                                setParticipantMuted(participant, action)
                            },
                            setVolume: { volumeLevel, synchronize in
                                setParticipantVolume(participant, volumeLevel, synchronize)
                            },
                            openConversation: {
                                openParticipantConversation(participant)
                            },
                            remove: {
                                removeParticipant(participant)
                            },
                            requestVideoView: requestVideoView,
                        )
                        .frame(width: videoWidth(video), height: tileHeight)
                    } else {
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

    private func participant(for video: ConferenceVideoPresentation) -> ConferenceParticipantPresentation? {
        participants.first(where: { $0.id == video.participantId })
    }

    private func videoWidth(_ video: ConferenceVideoPresentation) -> CGFloat {
        if isCompact {
            return video.isScreenSharing ? 136 : 88
        }
        return video.isScreenSharing ? 260 : 168
    }
}
