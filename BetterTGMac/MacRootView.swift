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
        } else {
            MacAuthorizationView(model: model)
        }
    }
}

// MARK: - MacAuthorizationView

private struct MacAuthorizationView: View {
    // MARK: Internal

    @Bindable var model: MacSessionModel

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "paperplane.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text("BetterTG")
                .font(.largeTitle.bold())

            Group {
                switch model.authorizationState {
                case .authorizationStateWaitPhoneNumber:
                    Text("Select your country and enter your phone number.")
                    countryButton
                    phoneNumberFields
                    Text(TelegramLoginGuidance.smsWarning)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                    Button("Continue") {
                        confirmsPhoneNumber = !model.phoneNumber.isEmpty
                    }
                    .keyboardShortcut(.defaultAction)
                case .authorizationStateWaitCode:
                    Text("Enter the code sent by Telegram.")
                    TextField("Login code", text: $model.loginCode)
                        .textContentType(.telephoneNumber)
                        .onSubmit { model.submitCode() }
                    Button("Sign In") { model.submitCode() }
                        .keyboardShortcut(.defaultAction)
                case .authorizationStateWaitPassword(let details):
                    Text(details.passwordHint.isEmpty
                        ? "Enter your two-step verification password."
                        : "Hint: \(details.passwordHint)")
                    SecureField("Password", text: $model.password)
                        .onSubmit { model.submitPassword() }
                    Button("Sign In") { model.submitPassword() }
                        .keyboardShortcut(.defaultAction)
                default:
                    ProgressView()
                    Text(model.authorizationStatus)
                        .foregroundStyle(.secondary)
                }
            }

            if let loginError = model.loginError {
                Text(loginError)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Login error: \(loginError)")
            }
        }
        .frame(width: 360)
        .padding(40)
        .sheet(isPresented: $showsCountryPicker) {
            MacCountryPicker(
                selectedCountry: model.selectedCountryNumber,
                countries: model.countryNumbers,
            ) { country in
                model.selectCountry(country)
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
            Button("Yes, continue") { model.submitPhoneNumber() }
            Button("Edit Number", role: .cancel) {}
        } message: {
            Text("Telegram will send the login code to \(model.formattedPhoneNumber).")
        }
    }

    // MARK: Private

    private enum PhoneField: Hashable {
        case callingCode
        case phoneNumber
    }

    @FocusState private var focusedPhoneField: PhoneField?
    @State private var confirmsPhoneNumber = false
    @State private var focusesPhoneNumberAfterCountrySelection = false
    @State private var showsCountryPicker = false

    private var countryAccessibilityLabel: String {
        guard let country = model.selectedCountryNumber else { return "Select Country" }
        return "Country: \(country.accessibilityLabel)"
    }

    private var countryButton: some View {
        Button {
            showsCountryPicker = true
        } label: {
            if let country = model.selectedCountryNumber {
                Text("\(country.flagEmoji) \(country.name)")
                    .lineLimit(1)
            } else {
                Text("Select Country")
            }
        }
        .accessibilityLabel(countryAccessibilityLabel)
        .accessibilityHint("Opens country picker")
    }

    private var phoneNumberFields: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("+")
                .accessibilityHidden(true)

            TextField("Code", text: $model.callingCode)
                .frame(width: 54)
                .textContentType(.telephoneNumber)
                .focused($focusedPhoneField, equals: .callingCode)
                .accessibilityLabel("Country calling code")
                .onChange(of: model.callingCode) { _, value in
                    let completedCode = model.updateCallingCode(value)
                    if completedCode, !showsCountryPicker, focusedPhoneField == .callingCode {
                        focusedPhoneField = .phoneNumber
                    }
                }
                .onSubmit { focusedPhoneField = .phoneNumber }

            TextField("Phone number", text: $model.phoneNumber)
                .textContentType(.telephoneNumber)
                .focused($focusedPhoneField, equals: .phoneNumber)
                .onSubmit { confirmsPhoneNumber = !model.phoneNumber.isEmpty }
        }
    }
}
