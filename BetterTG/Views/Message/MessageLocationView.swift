// MessageLocationView.swift

import SwiftUI
import TDLibKit

struct MessageLocationView: View {
    // MARK: Internal

    let content: MessageLocation
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: "location.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Location")
                        .foregroundStyle(.primary)
                    Text(coordinateText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Location: \(coordinateText)")
    }

    // MARK: Private

    private var coordinateText: String {
        String(format: "%.5f, %.5f", content.location.latitude, content.location.longitude)
    }
}
