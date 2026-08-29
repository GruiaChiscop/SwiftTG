// ConferenceVideoGrid.swift

import SwiftUI
import UIKit

// MARK: - ConferenceVideoGrid

struct ConferenceVideoGrid: View {
    // MARK: Internal

    let localVideoView: UIView?
    let isLocalScreenSharing: Bool
    let videos: [ConferenceVideoPresentation]
    let setExpanded: (Bool) -> Void
    let setUIHidden: (Bool) -> Void
    let setCentralVideo: (_ endpointId: String?, _ isExpanded: Bool) -> Void
    let requestVideoView: (String, @escaping @MainActor (UIView?) -> Void) -> Void

    var body: some View {
        Group {
            if isLocalVideoExpanded {
                VStack(spacing: 8) {
                    ConferenceLocalVideoStageView(
                        videoView: localVideoView,
                        isScreenSharing: isLocalScreenSharing,
                        isPinned: pinnedVideoId == localVideoId,
                        isUIHidden: isUIHidden,
                        collapse: collapseExpandedVideo,
                        togglePin: togglePin,
                        toggleUI: toggleUI,
                    )
                    .frame(maxHeight: .infinity)

                    ConferenceVideoStripView(
                        localVideoView: nil,
                        isLocalScreenSharing: false,
                        videos: videos,
                        isCompact: true,
                        selectLocalVideo: {},
                        selectVideo: expand,
                        requestVideoView: requestVideoView,
                    )
                    .frame(height: isUIHidden ? 0 : 104)
                    .opacity(isUIHidden ? 0 : 1)
                    .allowsHitTesting(!isUIHidden)
                    .accessibilityHidden(isUIHidden)
                }
            } else if let expandedVideo {
                VStack(spacing: 8) {
                    ConferenceVideoStageView(
                        video: expandedVideo,
                        isPinned: pinnedVideoId == expandedVideo.id,
                        isUIHidden: isUIHidden,
                        collapse: collapseExpandedVideo,
                        togglePin: togglePin,
                        toggleUI: toggleUI,
                        requestVideoView: requestVideoView,
                    )
                    .frame(maxHeight: .infinity)

                    ConferenceVideoStripView(
                        localVideoView: localVideoView,
                        isLocalScreenSharing: isLocalScreenSharing,
                        videos: videos.filter { $0.id != expandedVideo.id },
                        isCompact: true,
                        selectLocalVideo: expandLocalVideo,
                        selectVideo: expand,
                        requestVideoView: requestVideoView,
                    )
                    .frame(height: isUIHidden ? 0 : 104)
                    .opacity(isUIHidden ? 0 : 1)
                    .allowsHitTesting(!isUIHidden)
                    .accessibilityHidden(isUIHidden)
                }
            } else {
                ConferenceVideoStripView(
                    localVideoView: localVideoView,
                    isLocalScreenSharing: isLocalScreenSharing,
                    videos: videos,
                    isCompact: false,
                    selectLocalVideo: expandLocalVideo,
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
        .onChange(of: expandedVideoId, initial: true) { _, newValue in
            updateCentralVideo(newValue)
            setExpanded(newValue != nil)
            if newValue == nil {
                updateUIHidden(false)
            }
        }
        .task(id: focusedSpeakerAutoSwitchDeadline) {
            await waitForFocusedSpeakerAutoSwitch()
        }
        .onDisappear {
            setCentralVideo(nil, false)
            setExpanded(false)
            setUIHidden(false)
        }
    }

    // MARK: Private

    @State private var expandedVideoId: String?
    @State private var focusedSpeakerAutoSwitchDeadline = Date.distantPast
    @State private var isUIHidden = false
    @State private var pinnedVideoId: String?

    private var expandedVideo: ConferenceVideoPresentation? {
        guard let expandedVideoId else { return nil }
        return videos.first(where: { $0.id == expandedVideoId })
    }

    private var isLocalVideoExpanded: Bool {
        guard let localVideoId else { return false }
        return expandedVideoId == localVideoId
    }

    private var localVideoId: String? {
        if isLocalScreenSharing {
            return "local-screen"
        }
        if localVideoView != nil {
            return "local-camera"
        }
        return nil
    }

    private var speakingVideoId: String? {
        videos.first(where: { $0.isSpeaking && $0.isScreenSharing })?.id
            ?? videos.first(where: { $0.isSpeaking })?.id
    }

    private var videoIds: [String] {
        if let localVideoId {
            return [localVideoId] + videos.map(\.id)
        }
        return videos.map(\.id)
    }

    private func expand(_ video: ConferenceVideoPresentation) {
        let wasCollapsed = expandedVideoId == nil
        expandedVideoId = video.id
        pinnedVideoId = wasCollapsed && video.isScreenSharing ? video.id : nil
        focusedSpeakerAutoSwitchDeadline = .now.addingTimeInterval(3)
    }

    private func expandLocalVideo() {
        guard let localVideoId else { return }
        let wasCollapsed = expandedVideoId == nil
        expandedVideoId = localVideoId
        pinnedVideoId = wasCollapsed && isLocalScreenSharing ? localVideoId : nil
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
        if let pinnedVideoId, !videoIds.contains(pinnedVideoId) {
            self.pinnedVideoId = nil
        }
        guard let expandedVideoId else {
            if isLocalScreenSharing, let localVideoId {
                expandedVideoId = localVideoId
                pinnedVideoId = localVideoId
            } else if let screenShare = videos.first(where: \ConferenceVideoPresentation.isScreenSharing) {
                expandedVideoId = screenShare.id
                pinnedVideoId = screenShare.id
            }
            return
        }
        guard !videoIds.contains(expandedVideoId) else { return }
        if isLocalScreenSharing, let localVideoId {
            self.expandedVideoId = localVideoId
            pinnedVideoId = localVideoId
        } else if let screenShare = videos.first(where: \ConferenceVideoPresentation.isScreenSharing) {
            self.expandedVideoId = screenShare.id
            pinnedVideoId = screenShare.id
        } else if let firstVideo = videos.first {
            self.expandedVideoId = firstVideo.id
            pinnedVideoId = nil
            focusedSpeakerAutoSwitchDeadline = .now.addingTimeInterval(1)
        } else if let localVideoId {
            self.expandedVideoId = localVideoId
            pinnedVideoId = nil
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

    private func updateCentralVideo(_ videoId: String?) {
        guard let videoId else {
            setCentralVideo(nil, false)
            return
        }
        setCentralVideo(videos.first(where: { $0.id == videoId })?.endpointId, true)
    }

    private func toggleUI() {
        updateUIHidden(!isUIHidden)
    }

    private func updateUIHidden(_ isHidden: Bool) {
        isUIHidden = isHidden
        setUIHidden(isHidden)
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
