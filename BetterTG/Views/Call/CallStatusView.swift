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
        // `call` goes nil the instant the call ends, but this view can stay on screen after that
        // (e.g. while a terminal tone plays out) - an empty string here would render a `Text` with
        // no label, an accessibility element VoiceOver focuses on and reads nothing for.
        guard let call else { return "Call Ended" }
        switch call.state {
        case .callStatePending(let pending):
            if !call.isOutgoing {
                return "Incoming Call"
            }
            return pending.isReceived ? "Ringing…" : "Requesting…"
        case .callStateExchangingKeys, .callStateReady:
            return "Connecting…"
        case .callStateHangingUp:
            return "Ending…"
        case .callStateDiscarded, .callStateError:
            return "Call Ended"
        }
    }
}
