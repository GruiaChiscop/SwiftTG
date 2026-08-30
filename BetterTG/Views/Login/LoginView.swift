// LoginView.swift

import PhotosUI
import SwiftUI

struct LoginView: View {
    // MARK: Lifecycle

    init(
        service: any TelegramService = TDLib.shared.service,
        isPreview: Bool = false,
    ) {
        _model = State(initialValue: LoginViewModel(service: service, mode: isPreview ? .preview : .live))
    }

    // MARK: Internal

    @State var showSelectCountryView = false

    var body: some View {
        ZStack {
            Group {
                switch model.loginState {
                case .phoneNumber:
                    loginStateView {
                        VStack(spacing: 12) {
                            GroupBox {
                                HStack {
                                    Text("+")

                                    TextField("Country Code", text: $model.callingCode)
                                        .frame(width: 54)
                                        .focused($focused, equals: .callingCode)
                                        .keyboardType(.numberPad)
                                        .textContentType(.telephoneNumber)
                                        .onChange(of: model.callingCode) { _, value in
                                            let completedCode = model.updateCallingCode(value)
                                            if completedCode,
                                               !showSelectCountryView,
                                               focused == .callingCode
                                            {
                                                focused = .phoneNumber
                                            }
                                        }

                                    TextField("Phone Number", text: $model.phoneNumber)
                                        .focused($focused, equals: .phoneNumber)
                                        .keyboardType(.numberPad)
                                        .textContentType(.telephoneNumber)
                                }
                            } label: {
                                Button {
                                    showSelectCountryView.toggle()
                                } label: {
                                    if let country = model.selectedCountryNum {
                                        Text("\(country.flagEmoji) \(country.name)")
                                    } else {
                                        Text("Select Country")
                                    }
                                }
                            }

                            Text(TelegramLoginGuidance.smsWarning)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .sheet(isPresented: $showSelectCountryView) {
                        SelectCountryView(
                            showSelectCountryView: $showSelectCountryView,
                            countryNums: model.countryNums,
                        ) { country in
                            model.selectCountry(country)
                            focusesPhoneNumberAfterCountrySelection = true
                        }
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.hidden)
                    }
                    .onChange(of: showSelectCountryView) { _, isPresented in
                        guard !isPresented, focusesPhoneNumberAfterCountrySelection else { return }
                        focusesPhoneNumberAfterCountrySelection = false
                        focused = .phoneNumber
                    }
                case .code:
                    loginStateView {
                        VStack(spacing: 12) {
                            TextField("Code", text: $model.code)
                                .focused($focused, equals: .code)
                                .keyboardType(model.codeIsNumeric ? .numberPad : .default)
                                .textContentType(.oneTimeCode)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .submitLabel(.go)
                                .onSubmit { model.continueLogin() }
                                .onChange(of: model.code) { _, code in
                                    guard model.codeIsNumeric,
                                          let expected = model.expectedCodeLength,
                                          code.count == expected
                                    else { return }
                                    model.continueLogin()
                                }
                                .padding()
                                .background(Color.gray6)
                                .clipShape(.rect(cornerRadius: 10))

                            Text(model.codeDeliveryDescription)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Button {
                                model.resendCode()
                            } label: {
                                Text(model.codeResendCountdown > 0
                                    ? "\(model.codeResendActionTitle) in \(model.codeResendClock)"
                                    : model.codeResendActionTitle)
                            }
                            .font(.footnote)
                            .disabled(model.codeResendCountdown > 0 || model.isSubmittingCode)
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Button("Change Number") { model.changePhoneNumber() }
                                .font(.footnote)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .onAppear { focused = .code }
                case .twoFactor:
                    loginStateView {
                        VStack(spacing: 12) {
                            SecureField("Password", text: $model.twoFactor)
                                .focused($focused, equals: .twoFactor)
                                .textContentType(.password)
                                .keyboardType(.alphabet)
                                .submitLabel(.go)
                                .onSubmit { model.continueLogin() }
                                .padding()
                                .background(Color.gray6)
                                .clipShape(.rect(cornerRadius: 10))

                            Text(model.hint.isEmpty
                                ? "Enter your two-step verification password."
                                : "Hint: \(model.hint)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Button("Forgot Password?") {
                                model.startPasswordRecovery()
                            }
                            .font(.footnote)
                            .disabled(model.isRequestingPasswordRecovery)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                case .passwordRecovery:
                    loginStateView {
                        VStack(spacing: 12) {
                            TextField("Recovery Code", text: $model.recoveryCode)
                                .focused($focused, equals: .recoveryCode)
                                .keyboardType(.numberPad)
                                .textContentType(.oneTimeCode)
                                .padding()
                                .background(Color.gray6)
                                .clipShape(.rect(cornerRadius: 10))

                            SecureField("New Password", text: $model.newPassword)
                                .focused($focused, equals: .newPassword)
                                .textContentType(.newPassword)
                                .keyboardType(.alphabet)
                                .padding()
                                .background(Color.gray6)
                                .clipShape(.rect(cornerRadius: 10))

                            TextField("New Hint (optional)", text: $model.newPasswordHint)
                                .focused($focused, equals: .newPasswordHint)
                                .keyboardType(.alphabet)
                                .padding()
                                .background(Color.gray6)
                                .clipShape(.rect(cornerRadius: 10))

                            Text(model.recoveryEmailPattern.isEmpty
                                ? "Enter the code sent to your recovery email, then choose a new password."
                                : "Enter the code sent to \(model.recoveryEmailPattern), then choose a new password.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                case .emailAddress:
                    loginStateView {
                        VStack(spacing: 12) {
                            TextField("Enter your email", text: $model.emailAddress)
                                .focused($focused, equals: .emailAddress)
                                .keyboardType(.emailAddress)
                                .textContentType(.emailAddress)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .padding()
                                .background(Color.gray6)
                                .clipShape(.rect(cornerRadius: 10))

                            Text("Please enter your valid email address to protect your account.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                    }
                case .emailCode:
                    loginStateView {
                        VStack(spacing: 12) {
                            TextField("Code", text: $model.emailCode)
                                .onChange(of: model.emailCode) { _, code in
                                    if let expected = model.expectedEmailCodeLength, code.count == expected {
                                        model.continueLogin()
                                    }
                                }
                                .focused($focused, equals: .emailCode)
                                .keyboardType(.numberPad)
                                .padding()
                                .background(Color.gray6)
                                .clipShape(.rect(cornerRadius: 10))

                            if !model.emailAddressPattern.isEmpty {
                                Text("Please enter the code we have sent to your email \(model.emailAddressPattern).")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                    }
                case .registration:
                    loginStateView {
                        VStack(spacing: 12) {
                            registrationPhoto

                            TextField("First Name", text: $model.registrationFirstName)
                                .focused($focused, equals: .firstName)
                                .textContentType(.givenName)
                                .padding()
                                .background(Color.gray6)
                                .clipShape(.rect(cornerRadius: 10))

                            TextField("Last Name", text: $model.registrationLastName)
                                .focused($focused, equals: .lastName)
                                .textContentType(.familyName)
                                .padding()
                                .background(Color.gray6)
                                .clipShape(.rect(cornerRadius: 10))

                            Text("Enter your name and add a profile photo.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                    }
                }
            }
            .transition(
                .asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .leading),
                )
                .combined(with: .opacity),
            )
        }
        .animation(.default, value: model.loginState)
        .safeAreaInset(edge: .bottom) {
            Button {
                if model.loginState == .phoneNumber {
                    focused = nil
                }
                model.continueLogin()
            } label: {
                Group {
                    if model.isSubmittingCode {
                        ProgressView()
                    } else {
                        Text("Continue")
                    }
                }
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isSubmittingCode)
            .padding()
        }
        .alert(
            "Login Failed",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: {
                    if !$0 {
                        model.errorMessage = nil
                    }
                },
            ),
        ) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "Telegram couldn't complete the login.")
        }
        .alert("Error", isPresented: $model.waitPremiumErrorShown) {
            Text("In order to login, you need to upgrade to Telegram Premium. Please do it in the Telegram app.")
        }
        .alert(model.formattedPhoneNumber, isPresented: $model.showPhoneConfirmation) {
            Button("Edit", role: .cancel) {
                focused = .phoneNumber
            }
            Button("Yes") {
                model.submitPhoneNumber()
            }
        } message: {
            Text("Is this the correct number?")
        }
        .alert("Reset Account?", isPresented: $model.showsAccountResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset Account", role: .destructive) {
                model.resetAccount()
            }
        } message: {
            Text(
                "You have no recovery email set, so the password can't be restored. "
                    + "Resetting deletes this account and all its messages. This can't be undone.",
            )
        }
        .alert("Terms of Service", isPresented: $model.showsTermsConfirmation) {
            Button("Decline", role: .cancel) {}
            Button("Agree") {
                model.acceptTermsAndContinue()
            }
        } message: {
            Text(model.termsOfService?.text.text ?? "")
        }
        .task { await model.start() }
    }

    func loginStateView(_ content: () -> some View) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Text(model.loginState.title)
                .font(.system(.largeTitle, weight: .bold))
            Spacer()
            content()
            Spacer()
        }
        .padding()
    }

    // MARK: Private

    private enum FocusedField: Hashable {
        case callingCode
        case code
        case emailAddress
        case emailCode
        case firstName
        case lastName
        case newPassword
        case newPasswordHint
        case phoneNumber
        case recoveryCode
        case twoFactor
    }

    @FocusState private var focused: FocusedField?

    @State private var focusesPhoneNumberAfterCountrySelection = false
    @State private var model: LoginViewModel
    @State private var pickedRegistrationPhotoItem: PhotosPickerItem?

    private var registrationPhoto: some View {
        let hasPhoto = model.registrationPhotoData != nil
        return VStack(spacing: 10) {
            ZStack {
                if let data = model.registrationPhotoData, let image = Image(data: data) {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    Circle()
                        .fill(.quaternary)
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(width: 84, height: 84)
            .clipShape(Circle())
            .accessibilityHidden(true)

            PhotosPicker(selection: $pickedRegistrationPhotoItem, matching: .images) {
                Text(hasPhoto ? "Change Photo" : "Add Photo")
            }
        }
        .onChange(of: pickedRegistrationPhotoItem) { _, newValue in
            Task { @MainActor in
                guard let newValue, let data = try? await newValue.loadTransferable(type: Data.self) else { return }
                model.registrationPhotoData = data
            }
        }
    }
}
