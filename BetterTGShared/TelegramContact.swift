// TelegramContact.swift

import TDLibKit

// MARK: - TelegramContactPresentation

struct TelegramContactPresentation: Equatable, Sendable {
    // MARK: Lifecycle

    init(_ content: MessageContact) {
        let contact = content.contact
        self.firstName = contact.firstName
        self.lastName = contact.lastName
        self.phoneNumber = contact.phoneNumber
        self.userId = contact.userId
    }

    // MARK: Internal

    let firstName: String
    let lastName: String
    let phoneNumber: String
    let userId: Int64

    var displayName: String {
        [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ")
    }

    var hasTelegramAccount: Bool { userId != 0 }

    var contentDescription: String {
        var parts = ["Contact: \(displayName)"]
        if !phoneNumber.isEmpty {
            parts.append(phoneNumber)
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - DeviceContactRecord

/// A contact read from the device's system address book (`Contacts` framework) - kept free of
/// any `Contacts`/`CNContact` dependency so it can be shared with macOS, which has no such sync
/// step. iOS builds these via `PermissionsManager`/`SystemContactsAccess` and passes them in.
struct DeviceContactRecord: Equatable, Sendable {
    let firstName: String
    let lastName: String
    let phoneNumbers: [String]
}

// MARK: - TelegramContactPickerEntry

/// One selectable row in the contact-sharing composer's "My Contacts" list - either a Telegram
/// contact (`userId != 0`) or a device-only contact who isn't on Telegram (`userId == 0`), so
/// people without Telegram can still be shared, matching Telegram-iOS's own contact picker.
struct TelegramContactPickerEntry: Equatable, Identifiable, Sendable {
    let id: String
    let firstName: String
    let lastName: String
    let phoneNumber: String
    let userId: Int64

    var displayName: String {
        [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ")
    }

    var isOnTelegram: Bool { userId != 0 }
}

/// Merges Telegram-known contacts with device-only ones (people in the phone's address book
/// without a Telegram account), deduplicating by phone number so someone already resolved as a
/// Telegram user doesn't also show up as their own unresolved device entry.
func telegramContactPickerEntries(
    telegramUsers: [User],
    deviceContacts: [DeviceContactRecord],
) -> [TelegramContactPickerEntry] {
    let telegramEntries = telegramUsers.map { user in
        TelegramContactPickerEntry(
            id: "telegram-\(user.id)",
            firstName: user.firstName,
            lastName: user.lastName,
            phoneNumber: user.phoneNumber,
            userId: user.id,
        )
    }
    let knownPhoneKeys = Set(telegramEntries.compactMap { phoneDedupeKey($0.phoneNumber) })
    let deviceEntries = deviceContacts.flatMap { record -> [TelegramContactPickerEntry] in
        guard !record.firstName.isEmpty else { return [] }
        return record.phoneNumbers.compactMap { phoneNumber in
            guard !phoneNumber.filter(\.isNumber).isEmpty else { return nil }
            if let key = phoneDedupeKey(phoneNumber), knownPhoneKeys.contains(key) {
                return nil
            }
            return TelegramContactPickerEntry(
                id: "device-\(phoneNumber)",
                firstName: record.firstName,
                lastName: record.lastName,
                phoneNumber: phoneNumber,
                userId: 0,
            )
        }
    }
    return (telegramEntries + deviceEntries).sorted {
        $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
    }
}

/// Compares only the last 9 digits so that missing country/area code prefixes (`+40` vs. a local
/// `07...` dial form, for example) still count as a match; too-short numbers aren't reliable
/// enough to dedupe on and are left alone.
private func phoneDedupeKey(_ phoneNumber: String) -> String? {
    let digits = phoneNumber.filter(\.isNumber)
    guard digits.count >= 4 else { return nil }
    return String(digits.suffix(9))
}
