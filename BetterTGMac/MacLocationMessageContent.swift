// MacLocationMessageContent.swift

import SwiftUI
import TDLibKit

struct MacLocationMessageContent: View {
    // MARK: Internal

    let content: MessageLocation
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 8) {
                Image(systemName: "location.fill")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Location")
                    Text(coordinateText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHidden(true)
    }

    // MARK: Private

    private var coordinateText: String {
        String(format: "%.5f, %.5f", content.location.latitude, content.location.longitude)
    }
}
