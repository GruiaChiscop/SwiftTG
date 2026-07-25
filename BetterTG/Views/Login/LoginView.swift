// LoginView.swift

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
                        TextField("Code", text: $model.code)
                            .onChange(of: model.code) { _, code in
                                if let expectedCodeLength = model.expectedCodeLength,
                                   code.count == expectedCodeLength
                                {
                                    model.continueLogin()
                                }
                            }
                            .focused($focused, equals: .code)
                            .keyboardType(.numberPad)
                            .padding()
                            .background(Color.gray6)
                            .clipShape(.rect(cornerRadius: 10))
                    }
                case .twoFactor:
                    loginStateView {
                        SecureField(model.hint.isEmpty ? "2FA" : model.hint, text: $model.twoFactor)
                            .focused($focused, equals: .twoFactor)
                            .textContentType(.password)
                            .keyboardType(.alphabet)
                            .padding()
                            .background(Color.gray6)
                            .clipShape(.rect(cornerRadius: 10))
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
        #if DEBUG
        .safeAreaInset(edge: .top) {
            if !model.isPreview {
                Button("Load Mock Data") {
                    MockData.install()
                }
                .padding()
            }
        }
        #endif
        .safeAreaInset(edge: .bottom) {
                Button {
                    if model.loginState == .phoneNumber {
                        focused = nil
                    }
                    model.continueLogin()
                } label: {
                    Text("Continue")
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding()
            }
            .alert("Error", isPresented: $model.errorShown) {
                Text("There was an error with Authorization State. Please restart the app.")
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
        case phoneNumber
        case twoFactor
    }

    @FocusState private var focused: FocusedField?

    @State private var focusesPhoneNumberAfterCountrySelection = false
    @State private var model: LoginViewModel
}
