// AddContactSheet.swift

import SwiftUI
import TDLibKit

/// Adds a user you're already chatting with to your Telegram contacts. Mirrors Telegram-iOS's
/// peer-info "Add to Contacts" flow: an editable name plus an opt-in toggle for sharing your own
/// phone number. Presented from `ChatInfoView` / `MacChatInfoView`.
struct AddContactSheet: View {
    // MARK: Lifecycle

    init(
        userId: Int64,
        firstName: String,
        lastName: String,
        phoneNumber: String?,
        service: any TelegramService,
        onAdded: @escaping () -> Void,
    ) {
        self.userId = userId
        self.phoneNumber = phoneNumber
        self.service = service
        self.onAdded = onAdded
        _firstName = State(initialValue: firstName)
        _lastName = State(initialValue: lastName)
    }

    // MARK: Internal

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("First name", text: $firstName)
                    TextField("Last name", text: $lastName)
                }

                Section {
                    Toggle("Share My Phone Number", isOn: $sharePhoneNumber)
                } footer: {
                    Text("If on, this contact will be able to see your phone number.")
                }

                if isSaving {
                    Section {
                        ProgressView("Adding…")
                    }
                }
            }
            .navigationTitle("Add to Contacts")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", role: .cancel) { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") { Task { await add() } }
                            .disabled(isSaving || trimmedFirstName.isEmpty)
                    }
                }
                .alert("Couldn't Add Contact", isPresented: errorIsPresented) {
                    Button("OK") {}
                } message: {
                    Text(errorMessage ?? "")
                }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 260)
        #endif
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    @State private var firstName: String
    @State private var lastName: String
    @State private var sharePhoneNumber = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let userId: Int64
    private let phoneNumber: String?
    private let service: any TelegramService
    private let onAdded: () -> Void

    private var trimmedFirstName: String {
        firstName.trimmingCharacters(in: .whitespacesAndNewlines)
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

    @MainActor private func add() async {
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await service.addContact(
                contact: ImportedContact(
                    firstName: trimmedFirstName,
                    lastName: lastName.trimmingCharacters(in: .whitespacesAndNewlines),
                    note: nil,
                    phoneNumber: phoneNumber ?? "",
                ),
                sharePhoneNumber: sharePhoneNumber,
                userId: userId,
            )
            onAdded()
            dismiss()
        } catch {
            errorMessage = telegramErrorDescription(error)
        }
    }
}
