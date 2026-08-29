// MessageGroupCallView.swift

import SwiftUI
import TDLibKit

// MARK: - MessageGroupCallView

struct MessageGroupCallView: View {
    // MARK: Internal

    let content: MessageGroupCall
    let isOutgoing: Bool
    let messageDate: Int
    let dateText: String

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
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

                if let participantDescription = presentation.participantDescription {
                    Text(participantDescription)
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
        .task(id: messageDate) {
            guard content.duration == 0, !content.wasMissed else { return }
            let deadline = Foundation.Date(
                timeIntervalSince1970: TimeInterval(messageDate + TelegramGroupCallMessagePresentation.missedTimeout),
            )
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { return }
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled else { return }
            now = Foundation.Date()
        }
    }

    // MARK: Private

    @State private var now = Foundation.Date()

    private var presentation: TelegramGroupCallMessagePresentation {
        TelegramGroupCallMessagePresentation(
            content: content,
            isOutgoing: isOutgoing,
            messageDate: messageDate,
            now: now,
        )
    }

    private var statusText: String {
        guard let duration = presentation.durationDescription else { return dateText }
        return "\(dateText), \(duration)"
    }
}
