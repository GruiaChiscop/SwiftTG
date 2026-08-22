// CallVideoSurfaceContainerView.swift

@preconcurrency import TgVoipWebrtc
import UIKit

// MARK: - CallVideoSurfaceContainerView

/// Keeps tgcalls' Metal renderer at its native aspect ratio. The renderer itself fills whatever
/// bounds it receives, so its reported frame aspect and orientation must be applied by its host.
@MainActor final class CallVideoSurfaceContainerView: UIView {
    // MARK: Lifecycle

    init(videoView: UIView) {
        self.videoView = videoView
        self.videoRenderer = videoView as? any OngoingCallThreadLocalContextWebrtcVideoView
        super.init(frame: .zero)

        clipsToBounds = true
        backgroundColor = .black
        isUserInteractionEnabled = false

        videoView.alpha = 0.995
        addSubview(videoView)

        if let videoRenderer {
            self.orientation = videoRenderer.orientation
            self.aspect = Self.validAspect(videoRenderer.aspect)
            videoRenderer.setOnOrientationUpdated { [weak self] orientation, aspect in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.orientation = orientation
                    self.aspect = Self.validAspect(aspect)
                    self.setNeedsLayout()
                }
            }

            if let sampleBufferVideoView = videoView as? TelegramCallSampleBufferVideoView {
                self.mirrorHorizontally = sampleBufferVideoView.mirrorHorizontally
                self.mirrorVertically = sampleBufferVideoView.mirrorVertically
                videoRenderer.setOnIsMirroredUpdated { [weak self, weak sampleBufferVideoView] _ in
                    MainActor.assumeIsolated {
                        guard let self, let sampleBufferVideoView else { return }
                        self.mirrorHorizontally = sampleBufferVideoView.mirrorHorizontally
                        self.mirrorVertically = sampleBufferVideoView.mirrorVertically
                        self.setNeedsLayout()
                    }
                }
            }
        }
    }

    @available(*, unavailable) required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Internal

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !bounds.isEmpty else { return }

        let isSideways: Bool
        let rotation: CGFloat
        switch orientation {
        case .orientation0:
            isSideways = false
            rotation = 0
        case .orientation90:
            isSideways = true
            rotation = .pi / 2
        case .orientation180:
            isSideways = false
            rotation = .pi
        case .orientation270:
            isSideways = true
            rotation = -.pi / 2
        @unknown default:
            isSideways = false
            rotation = 0
        }

        let displayedAspect = isSideways ? 1 / aspect : aspect
        let displayedSize = Self.aspectFilledSize(aspect: displayedAspect, container: bounds.size)
        let rendererSize = isSideways
            ? CGSize(width: displayedSize.height, height: displayedSize.width)
            : displayedSize

        videoView.transform = .identity
        videoView.bounds = CGRect(origin: .zero, size: rendererSize)
        videoView.center = CGPoint(x: bounds.midX, y: bounds.midY)
        videoView.transform = CGAffineTransform(rotationAngle: rotation).scaledBy(
            x: mirrorHorizontally ? -1 : 1,
            y: mirrorVertically ? -1 : 1,
        )
    }

    // MARK: Private

    private static let fallbackAspect: CGFloat = 3 / 4

    private let videoView: UIView
    private let videoRenderer: (any OngoingCallThreadLocalContextWebrtcVideoView)?
    private var orientation = OngoingCallVideoOrientationWebrtc.orientation0
    private var aspect = fallbackAspect
    private var mirrorHorizontally = false
    private var mirrorVertically = false

    private static func validAspect(_ aspect: CGFloat) -> CGFloat {
        guard aspect.isFinite, aspect > 0.01 else { return fallbackAspect }
        return aspect
    }

    private static func aspectFilledSize(aspect: CGFloat, container: CGSize) -> CGSize {
        guard container.width > 0, container.height > 0 else { return .zero }
        if container.width / container.height > aspect {
            return CGSize(width: container.width, height: container.width / aspect)
        }
        return CGSize(width: container.height * aspect, height: container.height)
    }
}
