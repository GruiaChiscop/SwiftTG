// MacRootView.swift

import SwiftUI
import TDLibKit

// MARK: - MacRootView

struct MacRootView: View {
    @Bindable var model: MacSessionModel

    var body: some View {
        if case .authorizationStateReady = model.authorizationState {
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
                    Text("Enter your phone number including the country code.")
                    TextField("Phone number", text: $model.phoneNumber)
                        .textContentType(.telephoneNumber)
                        .onSubmit { confirmsPhoneNumber = !model.phoneNumber.isEmpty }
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
        .confirmationDialog(
            "Is this number correct?",
            isPresented: $confirmsPhoneNumber,
            titleVisibility: .visible,
        ) {
            Button("Yes, continue") { model.submitPhoneNumber() }
            Button("Edit Number", role: .cancel) {}
        } message: {
            Text("Telegram will send the login code to \(model.phoneNumber).")
        }
    }

    // MARK: Private

    @State private var confirmsPhoneNumber = false
}
