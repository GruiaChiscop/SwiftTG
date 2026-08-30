// MacSessionModel+Login.swift

import Foundation
import TDLibKit

extension MacSessionModel {
    func submitPhoneNumber() {
        guard let normalized = TelegramPhoneNumber.normalized(
            callingCode: callingCode,
            number: phoneNumber,
        ) else { return }
        wantsToChangePhoneNumber = false
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

    /// Ask Telegram to send the code again (via `codeInfo.nextType`). Disabled until the countdown
    /// from `codeInfo.timeout` reaches zero; the fresh `authorizationStateWaitCode` restarts it.
    func resendLoginCode() {
        guard codeResendCountdown == 0 else { return }
        runLoginRequest {
            try await self.service.resendAuthenticationCode()
        }
    }

    /// Go back to the phone-number step to fix a mistyped number. `step` reflects this via
    /// `wantsToChangePhoneNumber`; submitting again re-runs `setAuthenticationPhoneNumber`.
    func changePhoneNumberForLogin() {
        cancelCodeResendCountdown()
        loginCode = ""
        loginError = nil
        lastLoginCodeInfo = nil
        wantsToChangePhoneNumber = true
    }

    func startCodeResendCountdown(seconds: Int) {
        cancelCodeResendCountdown()
        codeResendCountdown = max(0, seconds)
        guard codeResendCountdown > 0 else { return }
        codeResendCountdownTask = Task { [weak self] in
            while let self, !Task.isCancelled, codeResendCountdown > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                codeResendCountdown -= 1
            }
        }
    }

    func cancelCodeResendCountdown() {
        codeResendCountdownTask?.cancel()
        codeResendCountdownTask = nil
    }

    func submitPassword() {
        guard !password.isEmpty else { return }
        runLoginRequest {
            try await self.service.checkAuthenticationPassword(password: self.password)
        }
    }

    /// "Forgot Password?" from the password step. With a recovery email on file, ask Telegram to
    /// send a code there and switch to the recovery step; otherwise the only way in is an account
    /// reset, so confirm that first.
    func startPasswordRecovery() {
        guard case .authorizationStateWaitPassword(let details) = authorizationState else { return }
        guard details.hasRecoveryEmailAddress else {
            showsAccountResetConfirmation = true
            return
        }
        loginError = nil
        Task {
            do {
                _ = try await service.requestAuthenticationPasswordRecovery()
                recoveryCode = ""
                newPassword = ""
                newPasswordHint = ""
                isRecoveringPassword = true
            } catch {
                loginError = TelegramLoginGuidance.errorDescription(error)
            }
        }
    }

    func submitPasswordRecovery() {
        let trimmed = recoveryCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !newPassword.isEmpty else { return }
        runLoginRequest {
            try await self.service.recoverAuthenticationPassword(
                recoveryCode: trimmed,
                newPassword: self.newPassword,
                newHint: self.newPasswordHint.isEmpty ? nil : self.newPasswordHint,
            )
        }
    }

    func resetAccount() {
        runLoginRequest {
            try await self.service.deleteAccount(reason: "Forgot password", password: nil)
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
