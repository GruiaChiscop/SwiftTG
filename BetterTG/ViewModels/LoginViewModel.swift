// LoginViewModel.swift

import Combine
import SwiftUI
import TDLibKit

@MainActor @Observable final class LoginViewModel {
    // MARK: Lifecycle

    init(service: any TelegramService) {
        self.service = service
    }

    // MARK: Internal

    var code = ""
    var countryNums = [PhoneNumberInfo]()
    var errorShown = false
    var hint = ""
    var loginState = LoginState.phoneNumber
    var phoneNumber = ""
    var selectedCountryNum = PhoneNumberInfo(
        country: "RU",
        phoneNumberPrefix: "7",
        name: "Russian Federation",
    )
    var showPhoneConfirmation = false
    var twoFactor = ""
    var waitPremiumErrorShown = false

    var formattedPhoneNumber: String {
        TelegramPhoneNumber.display(callingCode: selectedCountryNum.phoneNumberPrefix, number: phoneNumber)
    }

    func start() async {
        guard !started else { return }
        started = true
        observeAuthorizationState()

        async let authorizationState = try? service.getAuthorizationState()
        async let countries = try? service.getCountries()
        async let countryCode = try? service.getCountryCode()

        if let state = await authorizationState {
            apply(state)
        }
        if let countries = await countries?.countries,
           let countryCode = await countryCode?.text
        {
            apply(countries: countries, currentCountryCode: countryCode)
        }
    }

    func continueLogin() {
        switch loginState {
        case .phoneNumber:
            guard !phoneNumber.isEmpty else { return }
            showPhoneConfirmation = true
        case .code:
            Task { _ = try? await service.checkAuthenticationCode(code: code) }
        case .twoFactor:
            Task { _ = try? await service.checkAuthenticationPassword(password: twoFactor) }
        }
    }

    func submitPhoneNumber() {
        guard let number = TelegramPhoneNumber.normalized(
            callingCode: selectedCountryNum.phoneNumberPrefix,
            number: phoneNumber,
        ) else { return }
        Task {
            _ = try? await service.setAuthenticationPhoneNumber(phoneNumber: number, settings: nil)
        }
    }

    // MARK: Private

    @ObservationIgnored private var cancellables = Set<AnyCancellable>()
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
        case .authorizationStateWaitCode:
            loginState = .code
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

    private func apply(countries: [CountryInfo], currentCountryCode: String) {
        countryNums = TelegramPhoneNumber.countries(from: countries)
        if let info = TelegramPhoneNumber.country(for: currentCountryCode, in: countryNums) {
            selectedCountryNum = info
        }
    }
}
