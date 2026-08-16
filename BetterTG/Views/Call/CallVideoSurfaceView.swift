// CallVideoSurfaceView.swift

import SwiftUI
import UIKit

// MARK: - CallVideoSurfaceView

struct CallVideoSurfaceView: UIViewRepresentable {
    let videoView: UIView

    func makeUIView(context _: Context) -> UIView {
        CallVideoSurfaceContainerView(videoView: videoView)
    }

    func updateUIView(_: UIView, context _: Context) {}
}
