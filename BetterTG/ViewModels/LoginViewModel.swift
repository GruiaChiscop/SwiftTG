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
    var expectedCodeLength: Int?
    var countryNums = [PhoneNumberInfo]()
    var errorShown = false
    var hint = ""
    var loginState = LoginState.phoneNumber
    var phoneNumber = ""
    var selectedCountryNum: PhoneNumberInfo?
    var showPhoneConfirmation = false
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
            Task { _ = try? await service.checkAuthenticationCode(code: code) }
        case .twoFactor:
            Task { _ = try? await service.checkAuthenticationPassword(password: twoFactor) }
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
        Task {
            _ = try? await service.setAuthenticationPhoneNumber(phoneNumber: number, settings: nil)
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
            loginState = .twoFactor
            hint = value.passwordHint
        case .authorizationStateWaitCode(let details):
            loginState = .code
            expectedCodeLength = details.codeInfo.type.expectedLength
        case .authorizationStateWaitPhoneNumber:
            loginState = .phoneNumber
        case .authorizationStateClosed, .authorizationStateClosing, .authorizationStateLoggingOut:
            loginState = .phoneNumber
            errorShown = true
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
        case .twoFactor:
            break
        }
    }
}
