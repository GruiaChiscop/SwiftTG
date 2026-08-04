// TelegramIdentityBadge.swift

import SwiftUI
import TDLibKit

// MARK: - TelegramIdentityBadge

/// A single badge shown right after a person's name in the chat list - mirrors how Telegram-iOS
/// (`ChatListItem.swift`, "credibility icon") and Unigram (`IdentityIcon.cs`) both only ever show
/// one badge per row, in priority order.
enum TelegramIdentityBadge: Equatable, Sendable {
    case fake
    case premium
    case scam
    case verified

    // MARK: Internal

    var systemImage: String {
        switch self {
        case .fake, .scam: "exclamationmark.triangle.fill"
        case .premium: "star.fill"
        case .verified: "checkmark.seal.fill"
        }
    }

    var tint: Color {
        switch self {
        case .fake, .scam: .red
        case .premium: .yellow
        case .verified: .blue
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .fake: "Fake account"
        case .premium: "Premium account"
        case .scam: "Scam account"
        case .verified: "Verified"
        }
    }
}

extension User {
    /// Precedence matches Telegram-iOS's own chain (`ChatListItem.swift`): scam and fake outrank
    /// premium, which outranks a plain verified mark.
    var identityBadge: TelegramIdentityBadge? {
        if verificationStatus?.isScam == true {
            .scam
        } else if verificationStatus?.isFake == true {
            .fake
        } else if isPremium {
            .premium
        } else if verificationStatus?.isVerified == true {
            .verified
        } else {
            nil
        }
    }
}
