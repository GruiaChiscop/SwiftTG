import Contacts
import TDLibKit

final class PermissionsManager: @unchecked Sendable {
    static let shared = PermissionsManager()

    private let contactStore = CNContactStore()

    private init() {}

    @MainActor func requestPostLoginPermissions() async {
        await requestContactsAndSync()
    }

    @MainActor private func requestContactsAndSync() async {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        let allowed: Bool
        if status == .notDetermined {
            allowed = (try? await contactStore.requestAccess(for: .contacts)) == true
        } else {
            allowed = status == .authorized || status == .limited
        }
        guard allowed else { return }

        let store = contactStore
        Task.background {
            let keys: [CNKeyDescriptor] = [
                CNContactGivenNameKey as CNKeyDescriptor,
                CNContactFamilyNameKey as CNKeyDescriptor,
                CNContactPhoneNumbersKey as CNKeyDescriptor,
            ]
            let request = CNContactFetchRequest(keysToFetch: keys)
            var contacts = [ImportedContact]()
            try? store.enumerateContacts(with: request) { contact, _ in
                let firstName = String(contact.givenName.prefix(64))
                guard !firstName.isEmpty else { return }
                let lastName = String(contact.familyName.prefix(64))
                for number in contact.phoneNumbers {
                    contacts.append(ImportedContact(
                        firstName: firstName,
                        lastName: lastName,
                        note: nil,
                        phoneNumber: number.value.stringValue,
                    ))
                }
            }
            _ = try? await td.changeImportedContacts(contacts: contacts)
        }
    }

}
