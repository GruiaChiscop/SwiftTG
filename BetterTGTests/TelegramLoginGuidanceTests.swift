// TelegramLoginGuidanceTests.swift

@testable import BetterTG
import TDLibKit
import Testing

struct TelegramLoginGuidanceTests {
    @Test func `common authorization errors are presented in plain language`() {
        #expect(TelegramLoginGuidance.errorDescription(
            TDLibKit.Error(code: 400, message: "PHONE_CODE_INVALID"),
        ) == "The login code is incorrect.")
        #expect(TelegramLoginGuidance.errorDescription(
            TDLibKit.Error(code: 400, message: "PASSWORD_HASH_INVALID"),
        ) == "The two-step verification password is incorrect.")
        #expect(TelegramLoginGuidance.errorDescription(
            TDLibKit.Error(code: 429, message: "FLOOD_WAIT_60"),
        ) == "Too many attempts. Please wait before trying again.")
    }

    @Test func `unknown authorization errors preserve Telegram's useful message`() {
        #expect(TelegramLoginGuidance.errorDescription(
            TDLibKit.Error(code: 400, message: "A useful server message"),
        ) == "A useful server message")
    }
}
