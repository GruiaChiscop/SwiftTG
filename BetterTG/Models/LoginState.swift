// LoginState.swift

enum LoginState {
    case phoneNumber, code, twoFactor, emailAddress, emailCode, registration

    // MARK: Internal

    var title: String {
        switch self {
        case .phoneNumber: "Phone number"
        case .code: "Code"
        case .twoFactor: "2FA"
        case .emailAddress: "Add Email"
        case .emailCode: "Check Your Email"
        case .registration: "Your Info"
        }
    }
}
