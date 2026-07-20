// LoginView.swift

import SwiftUI

struct LoginView: View {
    // MARK: Lifecycle

    init(service: any TelegramService = TDLib.shared.service) {
        _model = State(initialValue: LoginViewModel(service: service))
    }

    // MARK: Internal

    @FocusState var focused: LoginState?
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
                                    if let country = model.selectedCountryNum {
                                        Text("+\(country.phoneNumberPrefix)")
                                    }

                                    TextField("Phone Number", text: $model.phoneNumber)
                                        .focused($focused, equals: .phoneNumber)
                                        .keyboardType(.numberPad)
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
                                .accessibilityLabel(countryAccessibilityLabel)
                                .accessibilityHint("Opens country picker")
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
                            selectedCountryNum: $model.selectedCountryNum,
                            countryNums: model.countryNums,
                        )
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.hidden)
                    }
                case .code:
                    loginStateView {
                        TextField("Code", text: $model.code)
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
            Button("Load Mock Data") {
                MockData.install()
            }
            .padding()
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

    @State private var model: LoginViewModel

    private var countryAccessibilityLabel: String {
        guard let country = model.selectedCountryNum else { return "Select Country" }
        return "Country: \(country.accessibilityLabel)"
    }
}
