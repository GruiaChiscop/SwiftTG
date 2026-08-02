// TelegramLoginGuidance.swift

import Foundation
import TDLibKit

enum TelegramLoginGuidance {
    static let smsWarning = "Important: Telegram may not deliver SMS or call login codes to third-party apps. If you have no other active Telegram session, or you are creating an account for the first time, use the official Telegram mobile app to sign in or create the account first."

    static func errorDescription(_ error: Swift.Error) -> String {
        guard let error = error as? TDLibKit.Error else {
            return error.localizedDescription
        }

        switch error.message.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "PHONE_NUMBER_INVALID":
            return "The phone number is invalid."
        case "PHONE_CODE_EMPTY":
            return "Enter the login code."
        case "PHONE_CODE_INVALID":
            return "The login code is incorrect."
        case "PHONE_CODE_EXPIRED":
            return "The login code has expired. Request a new code and try again."
        case "PASSWORD_HASH_INVALID":
            return "The two-step verification password is incorrect."
        case let message where message.hasPrefix("FLOOD_WAIT"):
            return "Too many attempts. Please wait before trying again."
        default:
            return telegramErrorDescription(error)
        }
    }
}
