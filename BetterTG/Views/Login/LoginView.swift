// LoginView.swift

import Combine
import SwiftUI
import TDLibKit

struct LoginView: View {
    // MARK: Internal

    @State var loginState = LoginState.phoneNumber
    
    @State var showSelectCountryView = false
    @State var selectedCountryNum = PhoneNumberInfo(country: "RU", phoneNumberPrefix: "7", name: "Russian Federation")
    
    @State var phoneNumber = ""
    @State var code = ""
    @State var hint = ""
    @State var twoFactor = ""
    
    @State var errorShown = false
    @State var waitPremiumErrorShown = false
    @State var showPhoneConfirmation = false
    @FocusState var focused: LoginState?
    
    var body: some View {
        ZStack {
            Group {
                switch loginState {
                case .phoneNumber:
                    loginStateView {
                        GroupBox {
                            HStack {
                                Text("+\(selectedCountryNum.phoneNumberPrefix)")
                                    
                                TextField("Phone Number", text: $phoneNumber)
                                    .focused($focused, equals: .phoneNumber)
                                    .keyboardType(.numberPad)
                            }
                        } label: {
                            Button(selectedCountryNum.name) {
                                showSelectCountryView.toggle()
                            }
                            .accessibilityLabel(
                                "Country: \(selectedCountryNum.name), +\(selectedCountryNum.phoneNumberPrefix)",
                            )
                            .accessibilityHint("Opens country picker")
                        }
                    }
                    .sheet(isPresented: $showSelectCountryView) {
                        SelectCountryView(
                            showSelectCountryView: $showSelectCountryView,
                            selectedCountryNum: $selectedCountryNum,
                        )
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.hidden)
                    }
                case .code:
                    loginStateView {
                        TextField("Code", text: $code)
                            .focused($focused, equals: .code)
                            .keyboardType(.numberPad)
                            .padding()
                            .background(Color.gray6)
                            .clipShape(.rect(cornerRadius: 10))
                    }
                case .twoFactor:
                    loginStateView {
                        SecureField(hint.isEmpty ? "2FA" : hint, text: $twoFactor)
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
        .animation(.default, value: loginState)
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
                continueLogin()
            } label: {
                Text("Continue")
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
        .alert("Error", isPresented: $errorShown) {
            Text("There was an error with Authorization State. Please restart the app.")
        }
        .alert("Error", isPresented: $waitPremiumErrorShown) {
            Text("In order to login, you need to upgrade to Telegram Premium. Please do it in the Telegram app.")
        }
        .alert(formattedPhoneNumber, isPresented: $showPhoneConfirmation) {
            Button("Edit", role: .cancel) {
                focused = .phoneNumber
            }
            Button("Yes") {
                submitPhoneNumber()
            }
        } message: {
            Text("Is this the correct number?")
        }
        .task {
            switch try? await td.getAuthorizationState() {
            case .authorizationStateWaitPassword: loginState = .twoFactor
            case .authorizationStateWaitCode: loginState = .code
            case .authorizationStateClosed, .authorizationStateClosing, .authorizationStateLoggingOut:
                errorShown = true
            case .authorizationStateWaitPremiumPurchase:
                waitPremiumErrorShown = true
            default: break
            }
        }
        .task { await loadCurrentCountry() }
        .onAppear(perform: setPublishers)
    }

    func loginStateView(_ content: () -> some View) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Text(loginState.title)
                .font(.system(.largeTitle, weight: .bold))
            Spacer()
            content()
            Spacer()
        }
        .padding()
    }

    // MARK: Private

    @State private var cancellables = Set<AnyCancellable>()

    private func loadCurrentCountry() async {
        guard let countries = try? await td.getCountries().countries,
              let countryCode = try? await td.getCountryCode().text,
              let country = countries.first(where: { $0.countryCode == countryCode })
        else { return }

        selectedCountryNum = PhoneNumberInfo(
            country: country.countryCode,
            phoneNumberPrefix: country.callingCodes[0],
            name: country.englishName,
        )
    }

    private var formattedPhoneNumber: String {
        "+\(selectedCountryNum.phoneNumberPrefix) \(phoneNumber)"
    }

    private func continueLogin() {
        switch loginState {
        case .phoneNumber:
            guard !phoneNumber.isEmpty else { return }
            focused = nil
            showPhoneConfirmation = true
        case .code:
            Task.background { _ = try? await td.checkAuthenticationCode(code: code) }
        case .twoFactor:
            Task.background { _ = try? await td.checkAuthenticationPassword(password: twoFactor) }
        }
    }

    private func submitPhoneNumber() {
        let number = "\(selectedCountryNum.phoneNumberPrefix)\(phoneNumber)"
        Task.background {
            _ = try? await td.setAuthenticationPhoneNumber(phoneNumber: number, settings: nil)
        }
    }

    private func setPublishers() {
        nc.publisher(&cancellables, for: .authorizationStateWaitPassword) { notification in
            guard let waitPassword = notification.object as? AuthorizationStateWaitPassword else { return }
            Task.main {
                loginState = .twoFactor
                withAnimation { hint = waitPassword.passwordHint }
            }
        }
        nc.publisher(&cancellables, for: .authorizationStateWaitCode) { _ in
            Task.main { loginState = .code }
        }
        nc.mergeMany(&cancellables, [
            .authorizationStateWaitPhoneNumber,
            .authorizationStateClosed,
            .authorizationStateClosing,
            .authorizationStateLoggingOut,
        ]) { _ in
            Task.main { loginState = .phoneNumber }
        }
    }
}
