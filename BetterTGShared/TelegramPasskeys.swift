// TelegramPasskeys.swift

import SwiftUI
@preconcurrency import TDLibKit

// MARK: - TelegramPasskeysView

struct TelegramPasskeysView: View {
    // MARK: Lifecycle

    init(service: any TelegramService, onCountChanged: @escaping (Int) -> Void = { _ in }) {
        self.service = service
        self.onCountChanged = onCountChanged
    }

    // MARK: Internal

    var body: some View {
        Group {
            if isLoading, passkeys.isEmpty {
                ProgressView("Loading Passkeys…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if passkeys.isEmpty {
                ContentUnavailableView(
                    "No Passkeys",
                    systemImage: "person.badge.key",
                    description: Text("Passkeys added to your Telegram account will appear here."),
                )
            } else {
                List(passkeys) { passkey in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(passkey.name)
                            .font(.headline)
                        Text(lastUsedText(for: passkey))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Remove Passkey", role: .destructive) {
                            passkeyPendingRemoval = passkey
                        }
                        .disabled(removingPasskeyIds.contains(passkey.id))
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Passkeys")
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await loadPasskeys()
        }
        .confirmationDialog(
            "Remove this passkey?",
            isPresented: confirmsRemoval,
            titleVisibility: .visible,
        ) {
            Button("Remove Passkey", role: .destructive) {
                guard let passkey = passkeyPendingRemoval else { return }
                Task { await remove(passkey) }
            }
            Button("Cancel", role: .cancel) { passkeyPendingRemoval = nil }
        } message: {
            Text("You won't be able to use it to sign in to Telegram anymore.")
        }
        .alert("Passkeys Error", isPresented: errorIsPresented) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Private

    @State private var errorMessage: String?
    @State private var hasLoaded = false
    @State private var isLoading = false
    @State private var passkeyPendingRemoval: Passkey?
    @State private var passkeys = [Passkey]()
    @State private var removingPasskeyIds = Set<String>()

    private let onCountChanged: (Int) -> Void
    private let service: any TelegramService

    private var confirmsRemoval: Binding<Bool> {
        Binding(
            get: { passkeyPendingRemoval != nil },
            set: { isPresented in
                if !isPresented {
                    passkeyPendingRemoval = nil
                }
            },
        )
    }

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

    private func lastUsedText(for passkey: Passkey) -> String {
        if passkey.lastUsageDate == 0 {
            let added = Date(timeIntervalSince1970: TimeInterval(passkey.additionDate))
                .formatted(date: .abbreviated, time: .omitted)
            return "Added \(added) · Never used"
        }
        let date = Date(timeIntervalSince1970: TimeInterval(passkey.lastUsageDate))
            .formatted(date: .abbreviated, time: .shortened)
        return "Last used \(date)"
    }

    @MainActor private func loadPasskeys() async {
        isLoading = true
        defer { isLoading = false }
        do {
            passkeys = try await service.getLoginPasskeys()
                .passkeys
                .sorted { $0.additionDate > $1.additionDate }
            onCountChanged(passkeys.count)
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }

    @MainActor private func remove(_ passkey: Passkey) async {
        removingPasskeyIds.insert(passkey.id)
        defer { removingPasskeyIds.remove(passkey.id) }
        do {
            _ = try await service.removeLoginPasskey(passkeyId: passkey.id)
            passkeys.removeAll { $0.id == passkey.id }
            passkeyPendingRemoval = nil
            onCountChanged(passkeys.count)
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }
}
