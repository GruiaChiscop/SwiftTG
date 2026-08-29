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
            errorMessage = nil
            Task {
                do {
                    _ = try await service.checkAuthenticationCode(code: code)
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

    private func observeAuthorizationState() {
        service.authorizationStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.apply(state)
            }
            .store(in: &cancellables)
    }

    private func apply(_ state: AuthorizationState) {
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
            expectedCodeLength = details.codeInfo.type.expectedLength
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
