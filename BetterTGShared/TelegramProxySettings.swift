// TelegramProxySettings.swift

import SwiftUI
@preconcurrency import TDLibKit

// MARK: - TelegramProxyType

enum TelegramProxyType: String, CaseIterable, Identifiable {
    case socks5
    case http
    case mtproto

    // MARK: Lifecycle

    init(_ type: ProxyType) {
        self =
            switch type {
            case .proxyTypeSocks5: .socks5
            case .proxyTypeHttp: .http
            case .proxyTypeMtproto: .mtproto
            }
    }

    // MARK: Internal

    var id: Self { self }

    var title: String {
        switch self {
        case .socks5: "SOCKS5"
        case .http: "HTTP"
        case .mtproto: "MTProto"
        }
    }
}

// MARK: - TelegramProxySettingsView

struct TelegramProxySettingsView: View {
    // MARK: Lifecycle

    init(service: any TelegramService) {
        self.service = service
    }

    // MARK: Internal

    var body: some View {
        List {
            Section {
                Button {
                    setEnabled(nil)
                } label: {
                    HStack {
                        Text("No Proxy")
                            .foregroundStyle(.primary)
                        Spacer()
                        if !hasEnabledProxy {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(hasEnabledProxy ? [] : [.isSelected])
                .disabled(isWorking)
            }

            Section("Proxies") {
                if proxies.isEmpty, hasLoaded {
                    Text("No proxies added yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(proxies) { proxy in
                    Button {
                        setEnabled(proxy.id)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(proxy.proxy.server):\(proxy.proxy.port)")
                                Text(TelegramProxyType(proxy.proxy.type).title + (proxy.comment.isEmpty
                                        ? ""
                                        : " · \(proxy.comment)"))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if proxy.isEnabled {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(proxy.isEnabled ? [.isSelected] : [])
                    .disabled(isWorking)
                    .swipeActions(edge: .trailing) {
                        Button("Delete", role: .destructive) {
                            Task { await remove(proxy) }
                        }
                        Button("Edit") {
                            editingProxy = proxy
                        }
                        .tint(.blue)
                    }
                    .contextMenu {
                        Button("Edit") { editingProxy = proxy }
                        Button("Delete", role: .destructive) {
                            Task { await remove(proxy) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Proxy")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isAddingProxy = true
                } label: {
                    Label("Add Proxy", systemImage: "plus")
                }
            }
        }
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await loadProxies()
        }
        .refreshable { await loadProxies() }
        .sheet(isPresented: $isAddingProxy, onDismiss: { Task { await loadProxies() } }) {
            TelegramProxyEditView(service: service, proxy: nil)
        }
        .sheet(item: $editingProxy, onDismiss: { Task { await loadProxies() } }) { proxy in
            TelegramProxyEditView(service: service, proxy: proxy)
        }
        .alert("Proxy operation failed", isPresented: errorIsPresented) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Private

    @State private var editingProxy: AddedProxy?
    @State private var errorMessage: String?
    @State private var hasLoaded = false
    @State private var isAddingProxy = false
    @State private var isWorking = false
    @State private var proxies = [AddedProxy]()

    private let service: any TelegramService

    private var hasEnabledProxy: Bool { proxies.contains { $0.isEnabled } }

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

    @MainActor private func loadProxies() async {
        do {
            proxies = try await service.getProxies().proxies
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }

    @MainActor private func setEnabled(_ proxyId: Int?) {
        guard !isWorking else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                _ =
                    if let proxyId {
                        try await service.enableProxy(proxyId: proxyId)
                    } else {
                        try await service.disableProxy()
                    }
                await loadProxies()
            } catch {
                errorMessage = telegramErrorDescription(error)
            }
        }
    }

    @MainActor private func remove(_ proxy: AddedProxy) async {
        do {
            _ = try await service.removeProxy(proxyId: proxy.id)
            await loadProxies()
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }
}

// MARK: - TelegramProxyEditView

private struct TelegramProxyEditView: View {
    // MARK: Lifecycle

    init(service: any TelegramService, proxy: AddedProxy?) {
        self.service = service
        self.proxy = proxy
        _server = State(initialValue: proxy?.proxy.server ?? "")
        _port = State(initialValue: proxy.map { String($0.proxy.port) } ?? "")
        _comment = State(initialValue: proxy?.comment ?? "")
        if let proxy {
            _proxyType = State(initialValue: TelegramProxyType(proxy.proxy.type))
            switch proxy.proxy.type {
            case .proxyTypeSocks5(let details):
                _username = State(initialValue: details.username)
                _password = State(initialValue: details.password)
            case .proxyTypeHttp(let details):
                _username = State(initialValue: details.username)
                _password = State(initialValue: details.password)
            case .proxyTypeMtproto(let details):
                _secret = State(initialValue: details.secret)
            }
        }
    }

    // MARK: Internal

    let service: any TelegramService
    let proxy: AddedProxy?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $proxyType) {
                        ForEach(TelegramProxyType.allCases) { type in
                            Text(type.title).tag(type)
                        }
                    }
                }

                Section {
                    TextField("Server", text: $server)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif
                        .autocorrectionDisabled()
                    TextField("Port", text: $port)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                }

                switch proxyType {
                case .http, .socks5:
                    Section {
                        TextField("Username (optional)", text: $username)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                            .autocorrectionDisabled()
                        SecureField("Password (optional)", text: $password)
                    }
                case .mtproto:
                    Section {
                        TextField("Secret", text: $secret)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                            .autocorrectionDisabled()
                    }
                }

                Section {
                    TextField("Comment (optional)", text: $comment)
                }

                if let pingResult {
                    Section {
                        Text(pingResult)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button("Test Connection") {
                        Task { await testConnection() }
                    }
                    .disabled(!isValid || isTesting)
                }
            }
            .navigationTitle(proxy == nil ? "Add Proxy" : "Edit Proxy")
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
        .alert("Couldn't Save Proxy", isPresented: errorIsPresented) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var comment: String
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var isTesting = false
    @State private var password = ""
    @State private var pingResult: String?
    @State private var port: String
    @State private var proxyType = TelegramProxyType.socks5
    @State private var secret = ""
    @State private var server: String
    @State private var username = ""

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

    private var isValid: Bool {
        guard !server.trimmingCharacters(in: .whitespaces).isEmpty, let portNumber = Int(port), portNumber > 0 else {
            return false
        }
        if proxyType == .mtproto {
            return !secret.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return true
    }

    private func buildProxyType() -> ProxyType {
        switch proxyType {
        case .socks5:
            .proxyTypeSocks5(ProxyTypeSocks5(password: password, username: username))
        case .http:
            .proxyTypeHttp(ProxyTypeHttp(httpOnly: false, password: password, username: username))
        case .mtproto:
            .proxyTypeMtproto(ProxyTypeMtproto(secret: secret))
        }
    }

    private func buildProxy() -> Proxy? {
        guard let portNumber = Int(port) else { return nil }
        return Proxy(port: portNumber, server: server.trimmingCharacters(in: .whitespaces), type: buildProxyType())
    }

    @MainActor private func testConnection() async {
        guard let newProxy = buildProxy() else { return }
        isTesting = true
        defer { isTesting = false }
        do {
            let seconds = try await service.pingProxy(proxy: newProxy)
            pingResult = String(format: "Connected - %.2fs", seconds.seconds)
        } catch {
            pingResult = nil
            errorMessage = telegramErrorDescription(error)
        }
    }

    @MainActor private func save() async {
        guard let newProxy = buildProxy() else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            _ =
                if let proxy {
                    try await service.editProxy(
                        comment: comment,
                        enable: proxy.isEnabled,
                        proxy: newProxy,
                        proxyId: proxy.id,
                    )
                } else {
                    try await service.addProxy(comment: comment, enable: true, proxy: newProxy)
                }
            dismiss()
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }
}
