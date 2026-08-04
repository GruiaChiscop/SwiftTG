// MacSessionModel+Login.swift

import Foundation
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

    func submitEmailAddress() {
        let trimmed = emailAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        runLoginRequest {
            try await self.service.setAuthenticationEmailAddress(emailAddress: trimmed)
        }
    }

    func submitEmailCode() {
        guard !emailCode.isEmpty else { return }
        runLoginRequest {
            try await self.service.checkAuthenticationEmailCode(
                code: .emailAddressAuthenticationCode(.init(code: self.emailCode)),
            )
        }
    }

    func submitRegistration() {
        let trimmedFirstName = registrationFirstName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFirstName.isEmpty else { return }
        if let registrationTermsOfService, registrationTermsOfService.showPopup, !hasAcceptedRegistrationTerms {
            showsRegistrationTermsConfirmation = true
            return
        }
        let trimmedLastName = registrationLastName.trimmingCharacters(in: .whitespacesAndNewlines)
        runLoginRequest {
            let result = try await self.service.registerUser(
                disableNotification: nil,
                firstName: trimmedFirstName,
                lastName: trimmedLastName,
            )
            if let registrationPhotoData = self.registrationPhotoData {
                let fileURL = FileManager.default
                    .temporaryDirectory
                    .appending(path: "\(UUID().uuidString).jpeg")
                try? registrationPhotoData.write(to: fileURL)
                _ = try? await self.service.setProfilePhoto(
                    isPublic: true,
                    photo: .inputChatPhotoStatic(.init(photo: .inputFileLocal(.init(path: fileURL.path)))),
                )
                try? FileManager.default.removeItem(at: fileURL)
            }
            return result
        }
    }

    func acceptRegistrationTermsAndContinue() {
        hasAcceptedRegistrationTerms = true
        submitRegistration()
    }

    func requestQrCodeLogin() {
        runLoginRequest {
            try await self.service.requestQrCodeAuthentication(otherUserIds: [])
        }
    }

    func cancelQrCodeLogin() {
        qrCodeLink = nil
        recreateSession()
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
