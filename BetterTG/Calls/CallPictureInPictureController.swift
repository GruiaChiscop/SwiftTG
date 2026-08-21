// CallPictureInPictureController.swift

import AVKit

// MARK: - CallPictureInPictureController

/// Owns AVKit's live-video Picture in Picture controller while the call session owns the source
/// renderer. The source is a separate tgcalls frame sink, so entering PiP never reparents the
/// renderer used by the full-screen call UI.
@MainActor final class CallPictureInPictureController: NSObject {
    // MARK: Lifecycle

    init?(videoView: TelegramCallSampleBufferVideoView, isIncoming: Bool) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return nil }

        self.isIncoming = isIncoming
        self.videoView = videoView
        let playbackDelegate = PlaybackDelegate()
        self.playbackDelegate = playbackDelegate
        let contentSource = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: videoView.sampleBufferLayer,
            playbackDelegate: playbackDelegate,
        )
        self.controller = AVPictureInPictureController(contentSource: contentSource)
        super.init()

        controller.delegate = self
        controller.requiresLinearPlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = false
    }

    // MARK: Internal

    let isIncoming: Bool
    let videoView: TelegramCallSampleBufferVideoView
    var restoreCallInterface: (((Bool) -> Void) -> Void)?

    @discardableResult func start() -> Bool {
        guard controller.isPictureInPicturePossible else { return false }
        controller.startPictureInPicture()
        return true
    }

    func stop() {
        if controller.isPictureInPictureActive {
            controller.stopPictureInPicture()
        }
    }

    // MARK: Private

    private let playbackDelegate: PlaybackDelegate
    private let controller: AVPictureInPictureController
}

// MARK: @preconcurrency AVPictureInPictureControllerDelegate

extension CallPictureInPictureController: @preconcurrency AVPictureInPictureControllerDelegate {
    func pictureInPictureController(
        _: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void,
    ) {
        guard let restoreCallInterface else {
            completionHandler(false)
            return
        }
        restoreCallInterface(completionHandler)
    }
}

// MARK: - PlaybackDelegate

private final class PlaybackDelegate: NSObject, AVPictureInPictureSampleBufferPlaybackDelegate {
    func pictureInPictureController(_: AVPictureInPictureController, setPlaying _: Bool) {}

    func pictureInPictureControllerTimeRangeForPlayback(
        _: AVPictureInPictureController,
    ) -> CMTimeRange {
        CMTimeRange(start: .zero, duration: .positiveInfinity)
    }

    func pictureInPictureControllerIsPlaybackPaused(_: AVPictureInPictureController) -> Bool {
        false
    }

    func pictureInPictureController(
        _: AVPictureInPictureController,
        didTransitionToRenderSize _: CMVideoDimensions,
    ) {}

    func pictureInPictureController(
        _: AVPictureInPictureController,
        skipByInterval _: CMTime,
        completion completionHandler: @escaping () -> Void,
    ) {
        completionHandler()
    }

    func pictureInPictureControllerShouldProhibitBackgroundAudioPlayback(
        _: AVPictureInPictureController,
    ) -> Bool {
        false
    }
}
