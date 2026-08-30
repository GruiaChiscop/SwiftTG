// LoginViewModel.swift

import Combine
import SwiftUI
import TDLibKit

@MainActor @Observable final class LoginViewModel {
    // MARK: Lifecycle

    init(service: any TelegramService, mode: Mode = .live) {
        self.service = service
        self.mode = mode
    }

    // MARK: Internal

    enum Mode {
        case live
        case preview
    }

    var callingCode = ""
    var code = ""
    var codePhoneNumber = ""
    var codeDeliveryType: AuthenticationCodeType?
    var codeNextType: AuthenticationCodeType?
    var codeResendCountdown = 0
    var isSubmittingCode = false
    var emailAddress = ""
    var emailAddressPattern = ""
    var emailCode = ""
    var expectedCodeLength: Int?
    var expectedEmailCodeLength: Int?
    var countryNums = [PhoneNumberInfo]()
    var errorMessage: String?
    var hasAcceptedTerms = false
    var hint = ""
    var loginState = LoginState.phoneNumber
    var phoneNumber = ""
    var hasRecoveryEmail = false
    var recoveryEmailPattern = ""
    var recoveryCode = ""
    var newPassword = ""
    var newPasswordHint = ""
    var showsAccountResetConfirmation = false
    var isRequestingPasswordRecovery = false
    var registrationFirstName = ""
    var registrationLastName = ""
    var registrationPhotoData: Data?
    var selectedCountryNum: PhoneNumberInfo?
    var showPhoneConfirmation = false
    var showsTermsConfirmation = false
    var termsOfService: TermsOfService?
    var twoFactor = ""
    var waitPremiumErrorShown = false

    var formattedPhoneNumber: String {
        TelegramPhoneNumber.display(callingCode: callingCode, number: phoneNumber)
    }

    var isPreview: Bool {
        mode == .preview
    }

    /// SMS-word and SMS-phrase codes are words, not digits - everything else is numeric.
    var codeIsNumeric: Bool {
        switch codeDeliveryType {
        case .authenticationCodeTypeSmsPhrase, .authenticationCodeTypeSmsWord:
            false
        default:
            true
        }
    }

    /// Sentence under the field explaining where the code was sent, from `codeInfo.type`.
    var codeDeliveryDescription: String {
        let target = codePhoneNumber.isEmpty ? "your phone" : codePhoneNumber
        switch codeDeliveryType {
        case .authenticationCodeTypeTelegramMessage:
            return "We sent the code to your other Telegram apps."
        case .authenticationCodeTypeFirebaseAndroid, .authenticationCodeTypeFirebaseIos, .authenticationCodeTypeSms,
             .authenticationCodeTypeSmsPhrase, .authenticationCodeTypeSmsWord:
            return "We sent an SMS with the code to \(target)."
        case .authenticationCodeTypeCall:
            return "Telegram is calling \(target) to dictate the code."
        case .authenticationCodeTypeMissedCall(let details):
            return "Telegram is calling \(target). Enter the last \(details.length) digits of the number that calls."
        case .authenticationCodeTypeFlashCall:
            return "Telegram is calling \(target); the call ends by itself."
        case .authenticationCodeTypeFragment:
            return "Your code is available on Fragment for \(target)."
        case .none:
            return "Enter the code you received."
        }
    }

    /// Label for the resend button, from `codeInfo.nextType` (how a resend would be delivered).
    var codeResendActionTitle: String {
        switch codeNextType {
        case .authenticationCodeTypeCall, .authenticationCodeTypeFlashCall, .authenticationCodeTypeMissedCall:
            "Call me with the code"
        case .authenticationCodeTypeTelegramMessage:
            "Send the code via Telegram"
        case .authenticationCodeTypeSms, .authenticationCodeTypeSmsPhrase, .authenticationCodeTypeSmsWord:
            "Send the code by SMS"
        case .authenticationCodeTypeFragment:
            "Get the code on Fragment"
        default:
            "Resend code"
        }
    }

    var codeResendClock: String {
        String(format: "%d:%02d", codeResendCountdown / 60, codeResendCountdown % 60)
    }

    func start() async {
        guard !started else { return }
        started = true
        guard mode == .live else {
            configurePreview()
            return
        }
        observeAuthorizationState()

        async let authorizationState = try? service.getAuthorizationState()
        async let countries = try? service.getCountries()
        async let countryCode = try? service.getCountryCode()

        if let state = await authorizationState {
            apply(state)
        }
        let resolvedCountries = await countries?.countries
        let resolvedCountryCode = await countryCode?.text
        if let resolvedCountries {
            apply(countries: resolvedCountries, currentCountryCode: resolvedCountryCode)
        }
    }

    func continueLogin() {
        if mode == .preview {
            continuePreview()
            return
        }

        switch loginState {
        case .phoneNumber:
            guard TelegramPhoneNumber.normalized(callingCode: callingCode, number: phoneNumber) != nil else { return }
            showPhoneConfirmation = true
        case .code:
            let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !isSubmittingCode else { return }
            errorMessage = nil
            isSubmittingCode = true
            Task {
                defer { isSubmittingCode = false }
                do {
                    _ = try await service.checkAuthenticationCode(code: trimmed)
                } catch {
                    guard !Task.isCancelled else { return }
                    errorMessage = TelegramLoginGuidance.errorDescription(error)
                }
            }
        case .twoFactor:
            errorMessage = nil
            Task {
                do {
                    _ = try await service.checkAuthenticationPassword(password: twoFactor)
                } catch {
                    guard !Task.isCancelled else { return }
                    errorMessage = TelegramLoginGuidance.errorDescription(error)
                }
            }
        case .passwordRecovery:
            let trimmedCode = recoveryCode.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedCode.isEmpty, !newPassword.isEmpty else { return }
            errorMessage = nil
            Task {
                do {
                    _ = try await service.recoverAuthenticationPassword(
                        recoveryCode: trimmedCode,
                        newPassword: newPassword,
                        newHint: newPasswordHint.isEmpty ? nil : newPasswordHint,
                    )
                } catch {
                    guard !Task.isCancelled else { return }
                    errorMessage = TelegramLoginGuidance.errorDescription(error)
                }
            }
        case .emailAddress:
            let trimmed = emailAddress.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            errorMessage = nil
            Task {
                do {
                    _ = try await service.setAuthenticationEmailAddress(emailAddress: trimmed)
                } catch {
                    guard !Task.isCancelled else { return }
                    errorMessage = TelegramLoginGuidance.errorDescription(error)
                }
            }
        case .emailCode:
            errorMessage = nil
            Task {
                do {
                    _ = try await service.checkAuthenticationEmailCode(
                        code: .emailAddressAuthenticationCode(.init(code: emailCode)),
                    )
                } catch {
                    guard !Task.isCancelled else { return }
                    errorMessage = TelegramLoginGuidance.errorDescription(error)
                }
            }
        case .registration:
            let trimmedFirstName = registrationFirstName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedFirstName.isEmpty else { return }
            if let termsOfService, termsOfService.showPopup, !hasAcceptedTerms {
                showsTermsConfirmation = true
                return
            }
            errorMessage = nil
            let trimmedLastName = registrationLastName.trimmingCharacters(in: .whitespacesAndNewlines)
            Task {
                do {
                    _ = try await service.registerUser(
                        disableNotification: nil,
                        firstName: trimmedFirstName,
                        lastName: trimmedLastName,
                    )
                    if let registrationPhotoData {
                        let fileURL = FileManager.default
                            .temporaryDirectory
                            .appending(path: "\(UUID().uuidString).jpeg")
                        try? registrationPhotoData.write(to: fileURL)
                        _ = try? await service.setProfilePhoto(
                            isPublic: true,
                            photo: .inputChatPhotoStatic(.init(photo: .inputFileLocal(.init(path: fileURL.path)))),
                        )
                        try? FileManager.default.removeItem(at: fileURL)
                    }
                } catch {
                    guard !Task.isCancelled else { return }
                    errorMessage = TelegramLoginGuidance.errorDescription(error)
                }
            }
        }
    }

    func acceptTermsAndContinue() {
        hasAcceptedTerms = true
        continueLogin()
    }

    /// Ask Telegram to send the code again (via `codeInfo.nextType`). Disabled until the countdown
    /// from `codeInfo.timeout` reaches zero; the resulting fresh `authorizationStateWaitCode`
    /// restarts that countdown.
    func resendCode() {
        guard mode == .live, codeResendCountdown == 0, !isSubmittingCode else { return }
        errorMessage = nil
        Task {
            do {
                _ = try await service.resendAuthenticationCode()
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = TelegramLoginGuidance.errorDescription(error)
            }
        }
    }

    /// Return to the phone-number step to fix a mistyped number. `callingCode`/`phoneNumber` stay
    /// filled in; submitting again re-runs `setAuthenticationPhoneNumber`, which TDLib accepts from
    /// `authorizationStateWaitCode`.
    func changePhoneNumber() {
        cancelCodeCountdown()
        code = ""
        errorMessage = nil
        lastCodeInfo = nil
        loginState = .phoneNumber
    }

    /// "Forgot Password?" from the password step. With a recovery email on file, ask Telegram to
    /// send a code there and move to the recovery step; without one, the only way back in is to
    /// reset the account, so confirm that first.
    func startPasswordRecovery() {
        guard mode == .live, !isRequestingPasswordRecovery else { return }
        guard hasRecoveryEmail else {
            showsAccountResetConfirmation = true
            return
        }
        isRequestingPasswordRecovery = true
        errorMessage = nil
        Task {
            defer { isRequestingPasswordRecovery = false }
            do {
                _ = try await service.requestAuthenticationPasswordRecovery()
                recoveryCode = ""
                newPassword = ""
                newPasswordHint = ""
                loginState = .passwordRecovery
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = TelegramLoginGuidance.errorDescription(error)
            }
        }
    }

    func resetAccount() {
        guard mode == .live else { return }
        errorMessage = nil
        Task {
            do {
                _ = try await service.deleteAccount(reason: "Forgot password", password: nil)
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = TelegramLoginGuidance.errorDescription(error)
            }
        }
    }

    func submitPhoneNumber() {
        if mode == .preview {
            showPhoneConfirmation = false
            loginState = .code
            expectedCodeLength = AuthenticationPreviewData.codeLength
            codePhoneNumber = TelegramPhoneNumber.display(callingCode: callingCode, number: phoneNumber)
            codeDeliveryType = .authenticationCodeTypeSms(.init(length: AuthenticationPreviewData.codeLength))
            codeNextType = .authenticationCodeTypeCall(.init(length: AuthenticationPreviewData.codeLength))
            codeResendCountdown = 0
            return
        }

        guard let number = TelegramPhoneNumber.normalized(callingCode: callingCode, number: phoneNumber) else { return }
        errorMessage = nil
        Task {
            do {
                _ = try await service.setAuthenticationPhoneNumber(phoneNumber: number, settings: nil)
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = TelegramLoginGuidance.errorDescription(error)
            }
        }
    }

    func selectCountry(_ country: PhoneNumberInfo) {
        selectedCountryNum = country
        callingCode = country.phoneNumberPrefix
        preferredCountryId = country.country
    }

    @discardableResult func updateCallingCode(_ value: String) -> Bool {
        let resolution = TelegramPhoneNumber.resolveCallingCode(
            value,
            countries: countryNums,
            preferredCountryId: preferredCountryId,
        )
        callingCode = resolution.callingCode
        selectedCountryNum = resolution.country
        return resolution.shouldAdvanceToNumber
    }

    // MARK: Private

    @ObservationIgnored private var cancellables = Set<AnyCancellable>()
    @ObservationIgnored private let mode: Mode
    @ObservationIgnored private var preferredCountryId: String?
    @ObservationIgnored private let service: any TelegramService
    @ObservationIgnored private var started = false
    @ObservationIgnored private var lastCodeInfo: AuthenticationCodeInfo?
    @ObservationIgnored private var codeCountdownTask: Task<Void, Never>?

    private func startCodeCountdown(seconds: Int) {
        cancelCodeCountdown()
        codeResendCountdown = max(0, seconds)
        guard codeResendCountdown > 0 else { return }
        codeCountdownTask = Task { [weak self] in
            while let self, !Task.isCancelled, codeResendCountdown > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                codeResendCountdown -= 1
            }
        }
    }

    private func cancelCodeCountdown() {
        codeCountdownTask?.cancel()
        codeCountdownTask = nil
    }

    private func observeAuthorizationState() {
        service.authorizationStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.apply(state)
            }
            .store(in: &cancellables)
    }

    private func apply(_ state: AuthorizationState) {
        if case .authorizationStateWaitCode = state {} else {
            cancelCodeCountdown()
        }
        switch state {
        case .authorizationStateWaitPassword(let value):
            if loginState != .passwordRecovery {
                loginState = .twoFactor
            }
            hint = value.passwordHint
            hasRecoveryEmail = value.hasRecoveryEmailAddress
            recoveryEmailPattern = value.recoveryEmailAddressPattern
        case .authorizationStateWaitCode(let details):
            loginState = .code
            guard details.codeInfo != lastCodeInfo else { break }
            lastCodeInfo = details.codeInfo
            let info = details.codeInfo
            expectedCodeLength = info.type.expectedLength
            codePhoneNumber = info.phoneNumber
            codeDeliveryType = info.type
            codeNextType = info.nextType
            startCodeCountdown(seconds: info.timeout)
        case .authorizationStateWaitPhoneNumber:
            loginState = .phoneNumber
        case .authorizationStateWaitEmailAddress:
            loginState = .emailAddress
        case .authorizationStateWaitEmailCode(let details):
            loginState = .emailCode
            emailAddressPattern = details.codeInfo.emailAddressPattern
            expectedEmailCodeLength = details.codeInfo.length > 0 ? details.codeInfo.length : nil
        case .authorizationStateWaitRegistration(let details):
            loginState = .registration
            termsOfService = details.termsOfService
            hasAcceptedTerms = false
        case .authorizationStateClosed, .authorizationStateClosing, .authorizationStateLoggingOut:
            loginState = .phoneNumber
            errorMessage = "The Telegram authorization session ended. Please try again."
        case .authorizationStateWaitPremiumPurchase:
            waitPremiumErrorShown = true
        default:
            break
        }
    }

    private func apply(countries: [CountryInfo], currentCountryCode: String?) {
        countryNums = TelegramPhoneNumber.countries(from: countries)
        if callingCode.isEmpty,
           let info = TelegramPhoneNumber.country(for: currentCountryCode, in: countryNums)
        {
            selectCountry(info)
        } else if callingCode.isEmpty {
            selectedCountryNum = nil
        } else {
            updateCallingCode(callingCode)
        }
    }

    private func configurePreview() {
        countryNums = AuthenticationPreviewData.countries
        if let country = countryNums.first {
            selectCountry(country)
        }
        phoneNumber = AuthenticationPreviewData.phoneNumber
    }

    private func continuePreview() {
        switch loginState {
        case .phoneNumber:
            guard TelegramPhoneNumber.normalized(callingCode: callingCode, number: phoneNumber) != nil else { return }
            showPhoneConfirmation = true
        case .code:
            guard !code.isEmpty else { return }
            hint = AuthenticationPreviewData.passwordHint
            loginState = .twoFactor
        case .emailAddress, .emailCode, .passwordRecovery, .registration, .twoFactor:
            break
        }
    }
}
