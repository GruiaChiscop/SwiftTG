// ConferenceVideoGrid.swift

import SwiftUI
import UIKit

// MARK: - ConferenceVideoGrid

struct ConferenceVideoGrid: View {
    // MARK: Internal

    let localVideoView: UIView?
    let isLocalScreenSharing: Bool
    let videos: [ConferenceVideoPresentation]
    let requestVideoView: (String, @escaping @MainActor (UIView?) -> Void) -> Void

    var body: some View {
        Group {
            if let expandedVideo {
                VStack(spacing: 8) {
                    ConferenceVideoStageView(
                        video: expandedVideo,
                        isPinned: pinnedVideoId == expandedVideo.id,
                        collapse: collapseExpandedVideo,
                        togglePin: togglePin,
                        requestVideoView: requestVideoView,
                    )
                    .frame(height: 260)

                    ConferenceVideoStripView(
                        localVideoView: localVideoView,
                        isLocalScreenSharing: isLocalScreenSharing,
                        videos: videos.filter { $0.id != expandedVideo.id },
                        isCompact: true,
                        selectVideo: expand,
                        requestVideoView: requestVideoView,
                    )
                    .frame(height: 104)
                }
            } else {
                ConferenceVideoStripView(
                    localVideoView: localVideoView,
                    isLocalScreenSharing: isLocalScreenSharing,
                    videos: videos,
                    isCompact: false,
                    selectVideo: expand,
                    requestVideoView: requestVideoView,
                )
                .frame(height: 200)
            }
        }
        .onChange(of: videoIds, initial: true) { _, _ in
            reconcileExpandedVideo()
        }
        .onChange(of: speakingVideoId) { _, newValue in
            switchToFocusedSpeakerIfNeeded(newValue)
        }
        .task(id: focusedSpeakerAutoSwitchDeadline) {
            await waitForFocusedSpeakerAutoSwitch()
        }
    }

    // MARK: Private

    @State private var expandedVideoId: String?
    @State private var focusedSpeakerAutoSwitchDeadline = Date.distantPast
    @State private var pinnedVideoId: String?

    private var expandedVideo: ConferenceVideoPresentation? {
        guard let expandedVideoId else { return nil }
        return videos.first(where: { $0.id == expandedVideoId })
    }

    private var speakingVideoId: String? {
        videos.first(where: { $0.isSpeaking && $0.isScreenSharing })?.id
            ?? videos.first(where: { $0.isSpeaking })?.id
    }

    private var videoIds: [String] {
        videos.map(\.id)
    }

    private func expand(_ video: ConferenceVideoPresentation) {
        let wasCollapsed = expandedVideoId == nil
        expandedVideoId = video.id
        pinnedVideoId = wasCollapsed && video.isScreenSharing ? video.id : nil
        focusedSpeakerAutoSwitchDeadline = .now.addingTimeInterval(3)
    }

    private func collapseExpandedVideo() {
        expandedVideoId = nil
        pinnedVideoId = nil
        focusedSpeakerAutoSwitchDeadline = .distantPast
    }

    private func togglePin() {
        guard let expandedVideoId else { return }
        pinnedVideoId = pinnedVideoId == expandedVideoId ? nil : expandedVideoId
    }

    private func reconcileExpandedVideo() {
        if let pinnedVideoId, !videos.contains(where: { $0.id == pinnedVideoId }) {
            self.pinnedVideoId = nil
        }
        guard let expandedVideoId else {
            if let screenShare = videos.first(where: \ConferenceVideoPresentation.isScreenSharing) {
                expandedVideoId = screenShare.id
                pinnedVideoId = screenShare.id
            }
            return
        }
        guard !videos.contains(where: { $0.id == expandedVideoId }) else { return }
        if let screenShare = videos.first(where: \ConferenceVideoPresentation.isScreenSharing) {
            self.expandedVideoId = screenShare.id
            pinnedVideoId = screenShare.id
        } else if let firstVideo = videos.first {
            self.expandedVideoId = firstVideo.id
            pinnedVideoId = nil
            focusedSpeakerAutoSwitchDeadline = .now.addingTimeInterval(1)
        } else {
            collapseExpandedVideo()
        }
    }

    private func switchToFocusedSpeakerIfNeeded(_ videoId: String?) {
        guard let videoId,
              expandedVideoId != nil,
              pinnedVideoId == nil,
              Date.now >= focusedSpeakerAutoSwitchDeadline,
              expandedVideoId != videoId
        else { return }
        expandedVideoId = videoId
        focusedSpeakerAutoSwitchDeadline = .now.addingTimeInterval(1)
    }

    private func waitForFocusedSpeakerAutoSwitch() async {
        let delay = focusedSpeakerAutoSwitchDeadline.timeIntervalSinceNow
        guard delay > 0 else { return }
        do {
            try await Task.sleep(for: .seconds(delay))
        } catch is CancellationError {
            return
        } catch {
            return
        }
        guard !Task.isCancelled else { return }
        switchToFocusedSpeakerIfNeeded(speakingVideoId)
    }
}
