// ForwardedFromView.swift

import SwiftUI

struct ForwardedFromView: View {
    // MARK: Lifecycle

    init(name: String, onTap: (() -> Void)? = nil) {
        self.name = name
        self.onTap = onTap
    }
    
    // MARK: Internal

    let name: String
    let onTap: (() -> Void)?

    var body: some View {
        Group {
            if let onTap {
                Button(action: onTap) { label }
                    .buttonStyle(.plain)
            } else {
                label
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 5)
    }

    // MARK: Private

    private var label: some View {
        HStack(spacing: 3) {
            Text("Forwarded from")
                .foregroundStyle(.white.opacity(0.6))
            Text(name)
                .bold()
                .lineLimit(1)
        }
    }
}
