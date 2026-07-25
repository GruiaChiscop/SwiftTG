// MacRootView.swift

import SwiftUI
import TDLibKit

// MARK: - MacRootView

struct MacRootView: View {
    @Bindable var model: MacSessionModel

    var body: some View {
        if model.sessionEnded {
            MacSessionEndedView(canReauthenticate: model.canReauthenticate) {
                model.reauthenticate()
            }
        } else if case .authorizationStateReady = model.authorizationState {
            MacChatWorkspace(model: model)
                #if DEBUG
                .toolbar {
                    ToolbarItem {
                        Button("Preview Login", systemImage: "person.crop.circle.badge.questionmark") {
                            showsLoginPreview = true
                        }
                    }
                }
                .sheet(isPresented: $showsLoginPreview) {
                    MacAuthorizationView(model: model, isPreview: true)
                }
                #endif
        } else {
            MacAuthorizationView(model: model)
        }
    }

    // MARK: Private

    #if DEBUG
    @State private var showsLoginPreview = false
    #endif
}

// MARK: - MacAuthorizationView

private struct MacAuthorizationView: View {
    // MARK: Internal

    @Bindable var model: MacSessionModel
    var isPreview = false

    var body: some View {
        VStack(spacing: 18) {
            if isPreview {
                HStack {
                    Spacer()
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
            }

            Image(systemName: "paperplane.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text("BetterTG")
                .font(.largeTitle.bold())

            Group {
                switch step {
                case .phoneNumber:
                    Text("Select your country and enter your phone number.")
                    countryButton
                    phoneNumberFields
                    Text(TelegramLoginGuidance.smsWarning)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                    Button("Continue") {
                        confirmsPhoneNumber = !phoneNumber.wrappedValue.isEmpty
                    }
                    .keyboardShortcut(.defaultAction)
                case .code:
                    Text("Enter the code sent by Telegram.")
                    TextField("Login code", text: loginCode)
                        .textContentType(.telephoneNumber)
                        .onSubmit { submitCode() }
                        .onChange(of: loginCode.wrappedValue) { _, code in
                            if let expectedLoginCodeLength,
                               code.count == expectedLoginCodeLength
                            {
                                submitCode()
                            }
                        }
                    Button("Log In") { submitCode() }
                        .keyboardShortcut(.defaultAction)
                case .password:
                    Text(passwordHint.isEmpty
                        ? "Enter your two-step verification password."
                        : "Hint: \(passwordHint)")
                    SecureField("Password", text: password)
                        .onSubmit { submitPassword() }
                    Button("Sign In") { submitPassword() }
                        .keyboardShortcut(.defaultAction)
                case nil:
                    ProgressView()
                    Text(model.authorizationStatus)
                        .foregroundStyle(.secondary)
                }
            }

            if !isPreview, let loginError = model.loginError {
                Text(loginError)
                    .foregroundStyle(.red)
            }
        }
        .frame(width: 360)
        .padding(40)
        .sheet(isPresented: $showsCountryPicker) {
            MacCountryPicker(
                selectedCountry: selectedCountry,
                countries: countries,
            ) { country in
                selectCountry(country)
                focusesPhoneNumberAfterCountrySelection = true
            }
        }
        .onChange(of: showsCountryPicker) { _, isPresented in
            guard !isPresented, focusesPhoneNumberAfterCountrySelection else { return }
            focusesPhoneNumberAfterCountrySelection = false
            focusedPhoneField = .phoneNumber
        }
        .confirmationDialog(
            "Is this number correct?",
            isPresented: $confirmsPhoneNumber,
            titleVisibility: .visible,
        ) {
            Button("Yes, continue") { submitPhoneNumber() }
            Button("Edit Number", role: .cancel) {}
        } message: {
            if isPreview {
                Text("Debug preview only. No request will be sent to Telegram.")
            } else {
                Text("Telegram will send the login code to \(formattedPhoneNumber).")
            }
        }
    }

    // MARK: Private

    private enum PhoneField: Hashable {
        case callingCode
        case phoneNumber
    }

    private enum Step {
        case phoneNumber
        case code
        case password
    }

    @FocusState private var focusedPhoneField: PhoneField?
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsPhoneNumber = false
    @State private var previewCallingCode = AuthenticationPreviewData.countries[0].phoneNumberPrefix
    @State private var previewLoginCode = ""
    @State private var previewPassword = ""
    @State private var previewPhoneNumber = AuthenticationPreviewData.phoneNumber
    @State private var previewSelectedCountry = AuthenticationPreviewData.countries[0]
    @State private var previewStep = Step.phoneNumber
    @State private var focusesPhoneNumberAfterCountrySelection = false
    @State private var showsCountryPicker = false

    private var callingCode: Binding<String> {
        Binding(
            get: { isPreview ? previewCallingCode : model.callingCode },
            set: {
                if isPreview {
                    previewCallingCode = $0
                } else {
                    model.callingCode = $0
                }
            },
        )
    }

    private var countries: [PhoneNumberInfo] {
        isPreview ? AuthenticationPreviewData.countries : model.countryNumbers
    }

    private var expectedLoginCodeLength: Int? {
        isPreview ? AuthenticationPreviewData.codeLength : model.expectedLoginCodeLength
    }

    private var formattedPhoneNumber: String {
        if isPreview {
            return TelegramPhoneNumber.display(
                callingCode: previewCallingCode,
                number: previewPhoneNumber,
            )
        }
        return model.formattedPhoneNumber
    }

    private var loginCode: Binding<String> {
        Binding(
            get: { isPreview ? previewLoginCode : model.loginCode },
            set: {
                if isPreview {
                    previewLoginCode = $0
                } else {
                    model.loginCode = $0
                }
            },
        )
    }

    private var password: Binding<String> {
        Binding(
            get: { isPreview ? previewPassword : model.password },
            set: {
                if isPreview {
                    previewPassword = $0
                } else {
                    model.password = $0
                }
            },
        )
    }

    private var passwordHint: String {
        if isPreview {
            return AuthenticationPreviewData.passwordHint
        }
        guard case .authorizationStateWaitPassword(let details) = model.authorizationState else { return "" }
        return details.passwordHint
    }

    private var phoneNumber: Binding<String> {
        Binding(
            get: { isPreview ? previewPhoneNumber : model.phoneNumber },
            set: {
                if isPreview {
                    previewPhoneNumber = $0
                } else {
                    model.phoneNumber = $0
                }
            },
        )
    }

    private var selectedCountry: PhoneNumberInfo? {
        isPreview ? previewSelectedCountry : model.selectedCountryNumber
    }

    private var step: Step? {
        if isPreview {
            return previewStep
        }
        switch model.authorizationState {
        case .authorizationStateWaitPhoneNumber:
            return .phoneNumber
        case .authorizationStateWaitCode:
            return .code
        case .authorizationStateWaitPassword:
            return .password
        default:
            return nil
        }
    }

    private var countryButton: some View {
        Button {
            showsCountryPicker = true
        } label: {
            if let country = selectedCountry {
                Text("\(country.flagEmoji) \(country.name)")
                    .lineLimit(1)
            } else {
                Text("Select Country")
            }
        }
    }

    private var phoneNumberFields: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("+")
            TextField("Country Code", text: callingCode, prompt: Text("1"))
                .frame(width: 54)
                .textContentType(.telephoneNumber)
                .focused($focusedPhoneField, equals: .callingCode)
                .onChange(of: callingCode.wrappedValue) { _, value in
                    let completedCode = updateCallingCode(value)
                    if completedCode, !showsCountryPicker, focusedPhoneField == .callingCode {
                        focusedPhoneField = .phoneNumber
                    }
                }
                .onSubmit { focusedPhoneField = .phoneNumber }

            TextField("Phone number", text: phoneNumber)
                .textContentType(.telephoneNumber)
                .focused($focusedPhoneField, equals: .phoneNumber)
                .onSubmit { confirmsPhoneNumber = !phoneNumber.wrappedValue.isEmpty }
        }
    }

    private func selectCountry(_ country: PhoneNumberInfo) {
        if isPreview {
            previewSelectedCountry = country
            previewCallingCode = country.phoneNumberPrefix
        } else {
            model.selectCountry(country)
        }
    }

    private func submitCode() {
        if isPreview {
            guard !previewLoginCode.isEmpty else { return }
            previewStep = .password
        } else {
            model.submitCode()
        }
    }

    private func submitPassword() {
        guard !isPreview else { return }
        model.submitPassword()
    }

    private func submitPhoneNumber() {
        if isPreview {
            confirmsPhoneNumber = false
            previewStep = .code
        } else {
            model.submitPhoneNumber()
        }
    }

    private func updateCallingCode(_ value: String) -> Bool {
        guard isPreview else { return model.updateCallingCode(value) }
        let resolution = TelegramPhoneNumber.resolveCallingCode(
            value,
            countries: countries,
            preferredCountryId: previewSelectedCountry.country,
        )
        previewCallingCode = resolution.callingCode
        if let country = resolution.country {
            previewSelectedCountry = country
        }
        return resolution.shouldAdvanceToNumber
    }
}
