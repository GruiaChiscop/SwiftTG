// LoginView.swift

import SwiftUI

struct LoginView: View {
    init(service: any TelegramService = TDLib.shared.service) {
        _model = State(initialValue: LoginViewModel(service: service))
    }

    // MARK: Internal

    @State var showSelectCountryView = false
    @FocusState var focused: LoginState?
    
    var body: some View {
        ZStack {
            Group {
                switch model.loginState {
                case .phoneNumber:
                    loginStateView {
                        GroupBox {
                            HStack {
                                Text("+\(model.selectedCountryNum.phoneNumberPrefix)")
                                    
                                TextField("Phone Number", text: $model.phoneNumber)
                                    .focused($focused, equals: .phoneNumber)
                                    .keyboardType(.numberPad)
                            }
                        } label: {
                            Button(model.selectedCountryNum.name) {
                                showSelectCountryView.toggle()
                            }
                            .accessibilityLabel(
                                "Country: \(model.selectedCountryNum.name), +\(model.selectedCountryNum.phoneNumberPrefix)",
                            )
                            .accessibilityHint("Opens country picker")
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
                if model.loginState == .phoneNumber { focused = nil }
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
}
