// MacRootView.swift

import PhotosUI
import SwiftUI
import TDLibKit

// MARK: - MacRootView

struct MacRootView: View {
    // MARK: Internal

    @Bindable var model: MacSessionModel

    var body: some View {
        if model.sessionEnded {
            MacSessionEndedView(canReauthenticate: model.canReauthenticate) {
                model.reauthenticate()
            }
        } else if case .authorizationStateReady = model.authorizationState {
            MacChatWorkspace(model: model)
                .task {
                    await TelegramKeepMediaPolicy.applyStoredPolicy(service: model.service)
                }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        TelegramNewChatMenu(service: model.service) { chat in
                            model.activateChat(chat.id)
                        }
                    }
                }
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

            Text("SwiftTG")
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
                    if !isPreview {
                        Button("Quick log in using QR code") {
                            model.requestQrCodeLogin()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)
                    }
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
                case .emailAddress:
                    Text("Please enter your valid email address to protect your account.")
                    TextField("Enter your email", text: $model.emailAddress)
                        .textContentType(.emailAddress)
                        .onSubmit { model.submitEmailAddress() }
                    Button("Continue") { model.submitEmailAddress() }
                        .keyboardShortcut(.defaultAction)
                case .emailCode:
                    if !model.emailAddressPattern.isEmpty {
                        Text("Please enter the code we have sent to your email \(model.emailAddressPattern).")
                    }
                    TextField("Code", text: $model.emailCode)
                        .onSubmit { model.submitEmailCode() }
                        .onChange(of: model.emailCode) { _, code in
                            if let expected = model.expectedEmailCodeLength, code.count == expected {
                                model.submitEmailCode()
                            }
                        }
                    Button("Continue") { model.submitEmailCode() }
                        .keyboardShortcut(.defaultAction)
                case .registration:
                    registrationPhoto
                    TextField("First Name", text: $model.registrationFirstName)
                        .textContentType(.givenName)
                    TextField("Last Name", text: $model.registrationLastName)
                        .textContentType(.familyName)
                    Text("Enter your name and add a profile photo.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                    Button("Continue") { model.submitRegistration() }
                        .keyboardShortcut(.defaultAction)
                case .qrCode:
                    qrCodeView
                    Text("Scan From Mobile Telegram")
                        .font(.headline)
                    Text("Open Telegram on your phone")
                    Text("Go to Settings > Devices > Link Desktop Device")
                    Text("Scan this image to Log In")
                    Button("Log in with phone number") {
                        model.cancelQrCodeLogin()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
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
        .confirmationDialog(
            "Terms of Service",
            isPresented: Binding(
                get: { !isPreview && model.showsRegistrationTermsConfirmation },
                set: {
                    if !$0 {
                        model.showsRegistrationTermsConfirmation = false
                    }
                },
            ),
            titleVisibility: .visible,
        ) {
            Button("Agree") { model.acceptRegistrationTermsAndContinue() }
            Button("Decline", role: .cancel) {}
        } message: {
            Text(model.registrationTermsOfService?.text.text ?? "")
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
        case emailAddress
        case emailCode
        case registration
        case qrCode
    }

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedPhoneField: PhoneField?
    @State private var confirmsPhoneNumber = false
    @State private var previewCallingCode = AuthenticationPreviewData.countries[0].phoneNumberPrefix
    @State private var previewLoginCode = ""
    @State private var previewPassword = ""
    @State private var previewPhoneNumber = AuthenticationPreviewData.phoneNumber
    @State private var previewSelectedCountry = AuthenticationPreviewData.countries[0]
    @State private var previewStep = Step.phoneNumber
    @State private var focusesPhoneNumberAfterCountrySelection = false
    @State private var showsCountryPicker = false
    @State private var pickedRegistrationPhotoItem: PhotosPickerItem?

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
        case .authorizationStateWaitEmailAddress:
            return .emailAddress
        case .authorizationStateWaitEmailCode:
            return .emailCode
        case .authorizationStateWaitRegistration:
            return .registration
        case .authorizationStateWaitOtherDeviceConfirmation:
            return .qrCode
        default:
            return nil
        }
    }

    private var registrationPhoto: some View {
        let hasPhoto = model.registrationPhotoData != nil
        return VStack(spacing: 10) {
            ZStack {
                if let data = model.registrationPhotoData, let nsImage = NSImage(data: data) {
                    Image(nsImage: nsImage)
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

    @ViewBuilder private var qrCodeView: some View {
        if let qrCodeLink = model.qrCodeLink, let cgImage = telegramQrCodeImage(for: qrCodeLink) {
            Image(nsImage: NSImage(cgImage: cgImage, size: NSSize(width: 200, height: 200)))
                .resizable()
                .interpolation(.none)
                .frame(width: 200, height: 200)
                .accessibilityLabel("QR code to scan with your phone's Telegram app")
        } else {
            ProgressView()
                .frame(width: 200, height: 200)
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
