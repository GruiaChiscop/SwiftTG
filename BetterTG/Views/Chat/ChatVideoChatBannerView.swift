// ChatVideoChatBannerView.swift

import SwiftUI
import TDLibKit

// MARK: - ChatVideoChatBannerView

struct ChatVideoChatBannerView: View {
    // MARK: Internal

    let call: GroupCall?
    let isChannel: Bool
    let join: () -> Void

    var body: some View {
        Button(action: join) {
            HStack(spacing: 12) {
                Image(systemName: isChannel ? "dot.radiowaves.left.and.right" : "waveform")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(.green, in: .circle)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(call?.scheduledStartDate ?? 0 > 0 ? "Open" : "Join")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: Private

    private var title: String {
        if let call, !call.title.isEmpty {
            return call.title
        }
        return isChannel ? "Live Stream" : "Voice Chat"
    }

    private var subtitle: String {
        guard let call else { return "Active now" }
        if call.scheduledStartDate > 0 {
            let date = Foundation.Date(
                timeIntervalSince1970: TimeInterval(call.scheduledStartDate),
            )
            .formatted(date: .abbreviated, time: .shortened)
            return "Scheduled for \(date)"
        }
        guard call.participantCount > 0 else { return "Active now" }
        return "\(call.participantCount) \(call.participantCount == 1 ? "participant" : "participants")"
    }
}
