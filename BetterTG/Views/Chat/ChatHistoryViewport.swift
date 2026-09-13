// ChatHistoryViewport.swift

import SwiftUI

/// Shared with hosted rows so a keyboard or window resize updates their text budgets without
/// replacing the table's content configurations (and their accessibility elements).
@MainActor @Observable final class ChatHistoryViewport {
    var height: CGFloat = 0

    var textPreviewHeight: CGFloat {
        // Leave room for sender/reply metadata and neighboring messages. The initial budget is
        // conservative until UIKit supplies the actual bounds of the history, excluding banners.
        height > 0 ? max(60, min(320, height * 0.45)) : 180
    }
}
