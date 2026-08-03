// MacSessionModel+Login.swift

import TDLibKit

extension MacSessionModel {
    func submitPhoneNumber() {
        guard let normalized = TelegramPhoneNumber.normalized(
            callingCode: callingCode,
            number: phoneNumber,
        ) else { return }
        runLoginRequest {
            try await self.service.setAuthenticationPhoneNumber(phoneNumber: normalized, settings: nil)
        }
    }

    func submitCode() {
        guard !loginCode.isEmpty else { return }
        runLoginRequest {
            try await self.service.checkAuthenticationCode(code: self.loginCode)
        }
    }

    func submitPassword() {
        guard !password.isEmpty else { return }
        runLoginRequest {
            try await self.service.checkAuthenticationPassword(password: self.password)
        }
    }

    func selectCountry(_ country: PhoneNumberInfo) {
        selectedCountryNumber = country
        callingCode = country.phoneNumberPrefix
        preferredCountryId = country.country
    }

    @discardableResult func updateCallingCode(_ value: String) -> Bool {
        let resolution = TelegramPhoneNumber.resolveCallingCode(
            value,
            countries: countryNumbers,
            preferredCountryId: preferredCountryId,
        )
        callingCode = resolution.callingCode
        selectedCountryNumber = resolution.country
        return resolution.shouldAdvanceToNumber
    }

    // MARK: Internal (called from `applyAuthorizationState` in the core file)

    func loadCountriesIfNeeded() {
        guard countryNumbers.isEmpty, countryLoadTask == nil else { return }
        countryLoadTask = Task { [weak self] in
            guard let self else { return }
            defer { countryLoadTask = nil }
            async let countriesResult = try? service.getCountries()
            async let countryCodeResult = try? service.getCountryCode()
            let countries = await countriesResult?.countries ?? []
            let currentCountryCode = await countryCodeResult?.text
            guard !Task.isCancelled else { return }

            let numbers = TelegramPhoneNumber.countries(from: countries)
            countryNumbers = numbers
            if callingCode.isEmpty,
               let current = TelegramPhoneNumber.country(for: currentCountryCode, in: numbers)
            {
                selectCountry(current)
            } else if callingCode.isEmpty {
                selectedCountryNumber = nil
            } else {
                updateCallingCode(callingCode)
            }
        }
    }

    // MARK: Private

    private func runLoginRequest(_ operation: @escaping @MainActor () async throws -> Ok) {
        loginError = nil
        Task {
            do {
                _ = try await operation()
            } catch {
                loginError = TelegramLoginGuidance.errorDescription(error)
            }
        }
    }
}
