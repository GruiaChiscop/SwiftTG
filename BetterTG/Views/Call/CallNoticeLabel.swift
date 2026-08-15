// CallNoticeLabel.swift

import SwiftUI

// MARK: - CallNoticeLabel

struct CallNoticeLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.footnote)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: .capsule)
    }
}
