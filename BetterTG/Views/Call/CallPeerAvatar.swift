// CallPeerAvatar.swift

import SwiftUI
import TDLibKit

// MARK: - CallPeerAvatar

struct CallPeerAvatar: View {
    // MARK: Internal

    let user: User?
    let fallbackTitle: String
    let userId: Int64?

    var body: some View {
        Group {
            if let photo = user?.profilePhoto?.big {
                AsyncTdImage(id: photo.id, maxPixelSize: 384) { image, _ in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .clipShape(.circle)
        // Purely decorative. `.accessibilityElement()` collapses the placeholder's initial (a bare
        // `Text`) into this element so it can't be focused on its own, then `.accessibilityHidden`
        // removes it - `.accessibilityHidden(true)` on the `Group` alone doesn't reliably reach
        // that nested `Text`.
        .accessibilityElement()
        .accessibilityHidden(true)
    }

    // MARK: Private

    private var placeholder: some View {
        PlaceholderView(
            title: fallbackTitle,
            id: userId ?? 0,
            fontSize: 48,
        )
    }
}
