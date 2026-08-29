// LoginState.swift

enum LoginState {
    case phoneNumber, code, twoFactor, passwordRecovery, emailAddress, emailCode, registration

    // MARK: Internal

    var title: String {
        switch self {
        case .phoneNumber: "Phone number"
        case .code: "Code"
        case .twoFactor: "Password"
        case .passwordRecovery: "Reset Password"
        case .emailAddress: "Add Email"
        case .emailCode: "Check Your Email"
        case .registration: "Your Info"
        }
    }
}
