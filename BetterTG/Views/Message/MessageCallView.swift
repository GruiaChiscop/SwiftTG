// MessageCallView.swift

import SwiftUI

// MARK: - MessageCallView

struct MessageCallView: View {
    // MARK: Internal

    let presentation: TelegramCallMessagePresentation
    let dateText: String

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(presentation.title)
                    .font(.body.bold())
                    .foregroundStyle(.white)

                HStack(spacing: 4) {
                    Image(systemName: presentation.directionSystemImage)
                        .font(.caption.bold())
                        .foregroundStyle(presentation.isSuccessful ? .green : .red)

                    Text(statusText)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.65))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: presentation.callSystemImage)
                .font(.body.bold())
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.15), in: .circle)
        }
        .frame(minWidth: 220, minHeight: 54)
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .contentShape(.rect)
    }

    // MARK: Private

    private var statusText: String {
        guard let duration = presentation.durationDescription else { return dateText }
        return "\(dateText), \(duration)"
    }
}
