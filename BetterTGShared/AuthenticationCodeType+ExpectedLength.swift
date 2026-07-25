// AuthenticationCodeType+ExpectedLength.swift

import TDLibKit

extension AuthenticationCodeType {
    var expectedLength: Int? {
        switch self {
        case .authenticationCodeTypeCall(let details):
            details.length
        case .authenticationCodeTypeFirebaseAndroid(let details):
            details.length
        case .authenticationCodeTypeFirebaseIos(let details):
            details.length
        case .authenticationCodeTypeFragment(let details):
            details.length
        case .authenticationCodeTypeMissedCall(let details):
            details.length
        case .authenticationCodeTypeSms(let details):
            details.length
        case .authenticationCodeTypeTelegramMessage(let details):
            details.length
        case .authenticationCodeTypeFlashCall,
             .authenticationCodeTypeSmsPhrase,
             .authenticationCodeTypeSmsWord:
            nil
        }
    }
}
