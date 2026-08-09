// TelegramTwoStepVerification.swift

import SwiftUI
@preconcurrency import TDLibKit

// MARK: - TelegramTwoStepVerificationView

struct TelegramTwoStepVerificationView: View {
    // MARK: Lifecycle

    init(service: any TelegramService) {
        self.service = service
    }

    // MARK: Internal

    var body: some View {
        Form {
            if let passwordState {
                Section {
                    LabeledContent("Two-Step Verification", value: passwordState.hasPassword ? "On" : "Off")
                    if passwordState.hasPassword, !passwordState.passwordHint.isEmpty {
                        LabeledContent("Hint", value: passwordState.passwordHint)
                    }
                } footer: {
                    Text(
                        passwordState.hasPassword
                            ? "You'll need this password in addition to the code from your phone when you sign in on a new device."
                            :
                            "Add an extra layer of security to your account: a password required at sign-in, in addition to the code sent by SMS or in-app.",
                    )
                }

                if passwordState.hasPassword, passwordState.pendingResetDate > 0 {
                    Section {
                        Text("A password reset was requested and will complete automatically if not cancelled.")
                            .foregroundStyle(.secondary)
                    }
                }

                if let codeInfo = passwordState.recoveryEmailAddressCodeInfo {
                    Section {
                        Button("Confirm Recovery Email") { showsRecoveryEmailCode = true }
                    } footer: {
                        Text(
                            "A confirmation code was sent to \(codeInfo.emailAddressPattern). "
                                + "Your recovery email won't be active until you confirm it.",
                        )
                    }
                }

                Section {
                    if passwordState.hasPassword {
                        Button("Change Password") { showsChangePassword = true }
                        Button(passwordState.hasRecoveryEmailAddress ? "Change Recovery Email" : "Add Recovery Email") {
                            showsChangeRecoveryEmail = true
                        }
                        Button("Turn Off Password", role: .destructive) { showsTurnOffPassword = true }
                    } else {
                        Button("Set Password") { showsSetPassword = true }
                    }
                }
            } else {
                Section {
                    ProgressView("Loading…")
                }
            }
        }
        .navigationTitle("Two-Step Verification")
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await loadState()
        }
        .sheet(isPresented: $showsSetPassword, onDismiss: { Task { await loadState() } }) {
            TelegramSetPasswordView(service: service, existingHint: nil)
        }
        .sheet(isPresented: $showsChangePassword, onDismiss: { Task { await loadState() } }) {
            TelegramSetPasswordView(service: service, existingHint: passwordState?.passwordHint)
        }
        .sheet(isPresented: $showsTurnOffPassword, onDismiss: { Task { await loadState() } }) {
            TelegramTurnOffPasswordView(service: service)
        }
        .sheet(isPresented: $showsChangeRecoveryEmail, onDismiss: { Task { await loadState() } }) {
            TelegramChangeRecoveryEmailView(
                service: service,
                existingHint: passwordState?.passwordHint ?? "",
                hasExistingRecoveryEmail: passwordState?.hasRecoveryEmailAddress ?? false,
            )
        }
        .sheet(isPresented: $showsRecoveryEmailCode, onDismiss: { Task { await loadState() } }) {
            if let codeInfo = passwordState?.recoveryEmailAddressCodeInfo {
                TelegramRecoveryEmailCodeView(service: service, codeInfo: codeInfo) { newState in
                    passwordState = newState
                    showsRecoveryEmailCode = false
                }
            }
        }
        .alert("Couldn't Load Password Settings", isPresented: errorIsPresented) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Private

    @State private var errorMessage: String?
    @State private var hasLoaded = false
    @State private var passwordState: PasswordState?
    @State private var showsChangePassword = false
    @State private var showsChangeRecoveryEmail = false
    @State private var showsRecoveryEmailCode = false
    @State private var showsSetPassword = false
    @State private var showsTurnOffPassword = false

    private let service: any TelegramService

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    errorMessage = nil
                }
            },
        )
    }

    @MainActor private func loadState() async {
        do {
            passwordState = try await service.getPasswordState()
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }
}

// MARK: - TelegramSetPasswordView

/// Handles both setting a brand-new password (no `existingHint`, current password left blank)
/// and changing an existing one (current password required before TDLib accepts the change).
private struct TelegramSetPasswordView: View {
    // MARK: Lifecycle

    init(service: any TelegramService, existingHint: String?) {
        self.service = service
        self.isChangingExistingPassword = existingHint != nil
        _hint = State(initialValue: existingHint ?? "")
    }

    // MARK: Internal

    let service: any TelegramService
    let isChangingExistingPassword: Bool

    var body: some View {
        NavigationStack {
            Form {
                if isChangingExistingPassword {
                    Section {
                        SecureField("Current Password", text: $currentPassword)
                    }
                }

                Section {
                    SecureField("New Password", text: $newPassword)
                    SecureField("Confirm New Password", text: $confirmPassword)
                } footer: {
                    if !newPassword.isEmpty, newPassword != confirmPassword {
                        Text("Passwords don't match.")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    TextField("Hint (optional)", text: $hint)
                }

                Section {
                    TextField("Recovery Email (optional)", text: $recoveryEmail)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        #endif
                        .autocorrectionDisabled()
                } footer: {
                    Text("If you forget your password, this is the only way to recover your account.")
                }
            }
            .navigationTitle(isChangingExistingPassword ? "Change Password" : "Set Password")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            Task { await save() }
                        }
                        .disabled(!isValid || isSaving)
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 420)
        #endif
        .sheet(isPresented: pendingCodeInfoIsPresented) {
            if let pendingCodeInfo {
                TelegramRecoveryEmailCodeView(service: service, codeInfo: pendingCodeInfo) { _ in
                    dismiss()
                }
            }
        }
        .alert("Couldn't Save Password", isPresented: errorIsPresented) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var confirmPassword = ""
    @State private var currentPassword = ""
    @State private var errorMessage: String?
    @State private var hint: String
    @State private var isSaving = false
    @State private var newPassword = ""
    @State private var pendingCodeInfo: EmailAddressAuthenticationCodeInfo?
    @State private var recoveryEmail = ""

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    errorMessage = nil
                }
            },
        )
    }

    private var pendingCodeInfoIsPresented: Binding<Bool> {
        Binding(
            get: { pendingCodeInfo != nil },
            set: { isPresented in
                if !isPresented {
                    pendingCodeInfo = nil
                }
            },
        )
    }

    private var isValid: Bool {
        guard !newPassword.isEmpty, newPassword == confirmPassword else { return false }
        if isChangingExistingPassword, currentPassword.isEmpty {
            return false
        }
        return true
    }

    @MainActor private func save() async {
        isSaving = true
        defer { isSaving = false }
        let trimmedEmail = recoveryEmail.trimmingCharacters(in: .whitespaces)
        do {
            let newState = try await service.setPassword(
                newHint: hint,
                newPassword: newPassword,
                newRecoveryEmailAddress: trimmedEmail,
                oldPassword: isChangingExistingPassword ? currentPassword : "",
                setRecoveryEmailAddress: !trimmedEmail.isEmpty,
            )
            if let codeInfo = newState.recoveryEmailAddressCodeInfo {
                pendingCodeInfo = codeInfo
            } else {
                dismiss()
            }
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }
}

// MARK: - TelegramChangeRecoveryEmailView

/// Changes only the recovery email, leaving the password itself untouched - `setPassword` is
/// still the call for this (TDLib has no separate endpoint), passing the current password back as
/// both `oldPassword` and `newPassword` and the existing hint back unchanged, matching how
/// Telegram-iOS's own `_internal_updateTwoStepVerificationEmail` does it (confirmed in its local
/// clone's `TwoStepVerification.swift`).
private struct TelegramChangeRecoveryEmailView: View {
    // MARK: Internal

    let service: any TelegramService
    let existingHint: String
    let hasExistingRecoveryEmail: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Password", text: $currentPassword)
                }
                Section {
                    TextField("Recovery Email", text: $newEmail)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        #endif
                        .autocorrectionDisabled()
                } footer: {
                    Text("If you forget your password, this is the only way to recover your account.")
                }
            }
            .navigationTitle(hasExistingRecoveryEmail ? "Change Recovery Email" : "Add Recovery Email")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            Task { await save() }
                        }
                        .disabled(!isValid || isSaving)
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 240)
        #endif
        .sheet(isPresented: pendingCodeInfoIsPresented) {
            if let pendingCodeInfo {
                TelegramRecoveryEmailCodeView(service: service, codeInfo: pendingCodeInfo) { _ in
                    dismiss()
                }
            }
        }
        .alert("Couldn't Save Recovery Email", isPresented: errorIsPresented) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var currentPassword = ""
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var newEmail = ""
    @State private var pendingCodeInfo: EmailAddressAuthenticationCodeInfo?

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    errorMessage = nil
                }
            },
        )
    }

    private var pendingCodeInfoIsPresented: Binding<Bool> {
        Binding(
            get: { pendingCodeInfo != nil },
            set: { isPresented in
                if !isPresented {
                    pendingCodeInfo = nil
                }
            },
        )
    }

    private var isValid: Bool {
        !currentPassword.isEmpty && !newEmail.trimmingCharacters(in: .whitespaces).isEmpty
    }

    @MainActor private func save() async {
        isSaving = true
        defer { isSaving = false }
        let trimmedEmail = newEmail.trimmingCharacters(in: .whitespaces)
        do {
            let newState = try await service.setPassword(
                newHint: existingHint,
                newPassword: currentPassword,
                newRecoveryEmailAddress: trimmedEmail,
                oldPassword: currentPassword,
                setRecoveryEmailAddress: true,
            )
            if let codeInfo = newState.recoveryEmailAddressCodeInfo {
                pendingCodeInfo = codeInfo
            } else {
                dismiss()
            }
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }
}

// MARK: - TelegramTurnOffPasswordView

private struct TelegramTurnOffPasswordView: View {
    // MARK: Internal

    let service: any TelegramService

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Current Password", text: $currentPassword)
                } footer: {
                    Text("Turning off Two-Step Verification removes the extra sign-in password from your account.")
                }
            }
            .navigationTitle("Turn Off Password")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Turn Off", role: .destructive) {
                            Task { await turnOff() }
                        }
                        .disabled(currentPassword.isEmpty || isSaving)
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 220)
        #endif
        .alert("Couldn't Turn Off Password", isPresented: errorIsPresented) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var currentPassword = ""
    @State private var errorMessage: String?
    @State private var isSaving = false

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    errorMessage = nil
                }
            },
        )
    }

    @MainActor private func turnOff() async {
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await service.setPassword(
                newHint: "",
                newPassword: "",
                newRecoveryEmailAddress: "",
                oldPassword: currentPassword,
                setRecoveryEmailAddress: false,
            )
            dismiss()
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }
}

// MARK: - TelegramRecoveryEmailCodeView

/// A recovery email set via `setPassword` isn't active until this code, sent to that address, is
/// confirmed - `PasswordState.recoveryEmailAddressCodeInfo` stays non-nil until then, from both
/// `setPassword`'s own return value and every later `getPasswordState` call.
private struct TelegramRecoveryEmailCodeView: View {
    // MARK: Internal

    let service: any TelegramService
    let codeInfo: EmailAddressAuthenticationCodeInfo
    let onCompletion: (PasswordState) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Enter the code sent to \(codeInfo.emailAddressPattern) to confirm your recovery email.")
                        .foregroundStyle(.secondary)
                }
                Section {
                    TextField("Code", text: $code)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .autocorrectionDisabled()
                }
                Section {
                    Button("Resend Code") { Task { await resend() } }
                        .disabled(isBusy)
                }
            }
            .navigationTitle("Confirm Recovery Email")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { Task { await cancel() } }
                            .disabled(isBusy)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Confirm") { Task { await confirm() } }
                            .disabled(code.isEmpty || isBusy)
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 260)
        #endif
        .alert("Couldn't Confirm Recovery Email", isPresented: errorIsPresented) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Private

    @State private var code = ""
    @State private var errorMessage: String?
    @State private var isBusy = false

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    errorMessage = nil
                }
            },
        )
    }

    @MainActor private func confirm() async {
        isBusy = true
        defer { isBusy = false }
        do {
            let newState = try await service.checkRecoveryEmailAddressCode(code: code)
            onCompletion(newState)
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }

    @MainActor private func resend() async {
        isBusy = true
        defer { isBusy = false }
        do {
            _ = try await service.resendRecoveryEmailAddressCode()
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }

    @MainActor private func cancel() async {
        isBusy = true
        defer { isBusy = false }
        do {
            let newState = try await service.cancelRecoveryEmailAddressVerification()
            onCompletion(newState)
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }
}
