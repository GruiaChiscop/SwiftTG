import Contacts
import TDLibKit

enum ContactsAuthorizationStatus: Sendable {
    case authorized
    case denied
    case notDetermined
}

struct DeviceContactRecord: Equatable, Sendable {
    let firstName: String
    let lastName: String
    let phoneNumbers: [String]
}

protocol ContactsAccess: Sendable {
    func authorizationStatus() -> ContactsAuthorizationStatus
    func requestAccess() async throws -> Bool
    func fetchContacts() throws -> [DeviceContactRecord]
}

final class SystemContactsAccess: ContactsAccess, @unchecked Sendable {
    private let store = CNContactStore()

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
}

final class PermissionsManager: Sendable {
    static let shared = PermissionsManager()

    private let contactsAccess: any ContactsAccess
    private let contactsSync: any TelegramContactsSyncing

    init(
        contactsAccess: any ContactsAccess = SystemContactsAccess(),
        contactsSync: any TelegramContactsSyncing = TDLib.shared.service,
    ) {
        self.contactsAccess = contactsAccess
        self.contactsSync = contactsSync
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

    @MainActor private func contactsAreAllowed() async -> Bool {
        switch contactsAccess.authorizationStatus() {
        case .authorized:
            true
        case .denied:
            false
        case .notDetermined:
            (try? await contactsAccess.requestAccess()) == true
        }
    }
}
