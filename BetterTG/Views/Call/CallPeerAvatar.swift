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
