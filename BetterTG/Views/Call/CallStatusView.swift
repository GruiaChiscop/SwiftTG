// CallStatusView.swift

import SwiftUI
import TDLibKit

// MARK: - CallStatusView

struct CallStatusView: View {
    // MARK: Internal

    let call: Call?
    let connectedAt: Foundation.Date?
    let engineState: TelegramCallEngine.State?
    let signalBars: Int?

    var body: some View {
        HStack(spacing: 6) {
            if engineState == .reconnecting {
                Text("Reconnecting…")
            } else if engineState == .failed {
                Text("Call Failed")
            } else if let connectedAt {
                TimelineView(.periodic(from: connectedAt, by: 1)) { context in
                    Text(telegramClockDuration(Int(context.date.timeIntervalSince(connectedAt))))
                        .monospacedDigit()
                }
            } else {
                Text(pendingStatusText)
            }

            if connectedAt != nil, engineState != .reconnecting, let signalBars {
                CallSignalBarsView(bars: signalBars)
            }
        }
    }

    // MARK: Private

    private var pendingStatusText: String {
        guard let call else { return "" }
        switch call.state {
        case .callStatePending:
            return call.isOutgoing ? "Calling…" : "Incoming Call"
        case .callStateExchangingKeys, .callStateReady:
            return "Connecting…"
        case .callStateHangingUp:
            return "Ending…"
        case .callStateDiscarded, .callStateError:
            return "Call Ended"
        }
    }
}
