// ConferenceLocalVideoStageView.swift

import SwiftUI
import UIKit

// MARK: - ConferenceLocalVideoStageView

struct ConferenceLocalVideoStageView: View {
    // MARK: Internal

    let videoView: UIView?
    let isScreenSharing: Bool
    let isPinned: Bool
    let isUIHidden: Bool
    let collapse: () -> Void
    let togglePin: () -> Void
    let toggleUI: () -> Void
    let setPinching: (Bool) -> Void

    var body: some View {
        ZStack(alignment: .top) {
            Button(action: toggleUI) {
                ConferenceLocalVideoTileView(
                    videoView: videoView,
                    isScreenSharing: isScreenSharing,
                    showsOverlay: !isUIHidden,
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(.plain)
            .accessibilityAction(.escape, collapse)
            .scaleEffect(magnification, anchor: magnificationAnchor)
            .zIndex(magnification > 1 ? 1 : 0)
            .simultaneousGesture(magnifyGesture)

            HStack {
                Button("Back to Video Grid", systemImage: "chevron.down", action: collapse)
                    .labelStyle(.iconOnly)

                Spacer()

                Button(
                    isPinned ? "Unpin" : "Pin",
                    systemImage: isPinned ? "pin.slash.fill" : "pin.fill",
                    action: togglePin,
                )
            }
            .font(.body.bold())
            .padding(10)
            .buttonStyle(.borderedProminent)
            .tint(.black.opacity(0.55))
            .opacity(isUIHidden ? 0 : 1)
            .allowsHitTesting(!isUIHidden)
            .accessibilityHidden(isUIHidden)
        }
        .onDisappear {
            setPinching(false)
        }
        .offset(y: verticalTranslation)
        .simultaneousGesture(collapseGesture)
    }

    // MARK: Private

    @GestureState private var magnification: CGFloat = 1
    @GestureState private var magnificationAnchor = UnitPoint.center
    @GestureState private var verticalTranslation: CGFloat = 0

    private var collapseGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .updating($verticalTranslation) { value, state, _ in
                guard magnification <= 1.01,
                      abs(value.translation.height) > abs(value.translation.width)
                else { return }
                state = value.translation.height
            }
            .onEnded { value in
                guard magnification <= 1.01,
                      abs(value.translation.height) > abs(value.translation.width)
                else { return }
                if abs(value.translation.height) >= 120
                    || abs(value.predictedEndTranslation.height) >= 220
                {
                    collapse()
                }
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .updating($magnification) { value, state, _ in
                state = min(3, max(1, value.magnification))
            }
            .updating($magnificationAnchor) { value, state, _ in
                state = value.startAnchor
            }
            .onChanged { _ in
                setPinching(true)
            }
            .onEnded { _ in
                setPinching(false)
            }
    }
}
