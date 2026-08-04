// PermissionsManager.swift

import Contacts
import TDLibKit

// MARK: - ContactsAuthorizationStatus

enum ContactsAuthorizationStatus: Sendable {
    case authorized
    case denied
    case notDetermined
}

// MARK: - ContactsAccess

protocol ContactsAccess: Sendable {
    func authorizationStatus() -> ContactsAuthorizationStatus
    func requestAccess() async throws -> Bool
    func fetchContacts() throws -> [DeviceContactRecord]
}

// MARK: - SystemContactsAccess

final class SystemContactsAccess: ContactsAccess, @unchecked Sendable {
    // MARK: Internal

    func authorizationStatus() -> ContactsAuthorizationStatus {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized, .limited:
            .authorized
        case .notDetermined:
            .notDetermined
        case .denied, .restricted:
            .denied
        @unknown default:
            .denied
        }
    }

    func requestAccess() async throws -> Bool {
        try await store.requestAccess(for: .contacts)
    }

    func fetchContacts() throws -> [DeviceContactRecord] {
        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)
        var contacts = [DeviceContactRecord]()
        try store.enumerateContacts(with: request) { contact, _ in
            contacts.append(DeviceContactRecord(
                firstName: contact.givenName,
                lastName: contact.familyName,
                phoneNumbers: contact.phoneNumbers.map(\.value.stringValue),
            ))
        }
        return contacts
    }

    // MARK: Private

    private let store = CNContactStore()
}

// MARK: - PermissionsManager

final class PermissionsManager: Sendable {
    // MARK: Lifecycle

    init(
        contactsAccess: any ContactsAccess = SystemContactsAccess(),
        contactsSync: any TelegramContactsSyncing = TDLib.shared.service,
    ) {
        self.contactsAccess = contactsAccess
        self.contactsSync = contactsSync
    }

    // MARK: Internal

    static let shared = PermissionsManager()

    /// Safe to read on every render - `CNContactStore.authorizationStatus(for:)` is a cheap,
    /// synchronous system call, unlike expensive on-device work such as `NLLanguageRecognizer`.
    var contactsAuthorizationStatus: ContactsAuthorizationStatus {
        contactsAccess.authorizationStatus()
    }

    static func importedContacts(from records: [DeviceContactRecord]) -> [ImportedContact] {
        records.flatMap { record -> [ImportedContact] in
            let firstName = String(record.firstName.prefix(64))
            guard !firstName.isEmpty else { return [] }
            let lastName = String(record.lastName.prefix(64))
            return record.phoneNumbers.map { phoneNumber in
                ImportedContact(
                    firstName: firstName,
                    lastName: lastName,
                    note: nil,
                    phoneNumber: phoneNumber,
                )
            }
        }
    }

    /// Used by the contact-sharing composer's "My Contacts" tab to also offer people from the
    /// phone's address book who aren't on Telegram. Returns nothing when access isn't currently
    /// authorized - this never itself prompts, unlike `requestPostLoginPermissions()`.
    func fetchDeviceContactsIfAuthorized() async -> [DeviceContactRecord] {
        guard contactsAuthorizationStatus == .authorized else { return [] }
        let access = contactsAccess
        return await Task.detached(priority: .utility) {
            (try? access.fetchContacts()) ?? []
        }.value
    }

    func requestPostLoginPermissions() async {
        guard await contactsAreAllowed() else { return }

        let access = contactsAccess
        let records = await Task.detached(priority: .utility) {
            try? access.fetchContacts()
        }.value
        guard let records else { return }

        let contacts = Self.importedContacts(from: records)
        _ = try? await contactsSync.changeImportedContacts(contacts: contacts)
    }

    // MARK: Private

    private let contactsAccess: any ContactsAccess
    private let contactsSync: any TelegramContactsSyncing

    @MainActor private func contactsAreAllowed() async -> Bool {
        switch contactsAccess.authorizationStatus() {
        case .authorized:
            true
        case .denied:
            false
        case .notDetermined:
            await (try? contactsAccess.requestAccess()) == true
        }
    }
}
