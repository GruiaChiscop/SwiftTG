// CallPictureInPictureController.swift

import AVKit

// MARK: - CallPictureInPictureController

/// Owns AVKit's video-call Picture in Picture controller and an independent tgcalls frame sink,
/// so entering PiP never reparents the renderer used by the full-screen call UI.
@MainActor final class CallPictureInPictureController: NSObject {
    // MARK: Lifecycle

    init?(videoView: TelegramCallSampleBufferVideoView, isIncoming: Bool) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return nil }

        self.isIncoming = isIncoming
        let sourceView = UIView()
        self.sourceView = sourceView
        let contentViewController = AVPictureInPictureVideoCallViewController()
        let videoContainerView = CallVideoSurfaceContainerView(videoView: videoView)
        videoContainerView.frame = contentViewController.view.bounds
        videoContainerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentViewController.view.backgroundColor = .black
        contentViewController.view.addSubview(videoContainerView)
        self.contentViewController = contentViewController
        let contentSource = AVPictureInPictureController.ContentSource(
            activeVideoCallSourceView: sourceView,
            contentViewController: contentViewController,
        )
        self.controller = AVPictureInPictureController(contentSource: contentSource)
        super.init()

        controller.delegate = self
        controller.canStartPictureInPictureAutomaticallyFromInline = true
    }

    // MARK: Internal

    let isIncoming: Bool
    let sourceView: UIView
    var didFailToStartPictureInPicture: (() -> Void)?
    var didStartPictureInPicture: (() -> Void)?
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

    private let contentViewController: AVPictureInPictureVideoCallViewController
    private let controller: AVPictureInPictureController
}

// MARK: @preconcurrency AVPictureInPictureControllerDelegate

extension CallPictureInPictureController: @preconcurrency AVPictureInPictureControllerDelegate {
    func pictureInPictureController(
        _: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: any Error,
    ) {
        log("[Call] Picture in Picture failed to start: \(error)")
        didFailToStartPictureInPicture?()
    }

    func pictureInPictureControllerDidStartPictureInPicture(_: AVPictureInPictureController) {
        didStartPictureInPicture?()
    }

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
