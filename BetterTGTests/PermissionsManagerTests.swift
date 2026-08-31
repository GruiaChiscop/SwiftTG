// PermissionsManagerTests.swift

@testable import BetterTG
import Foundation
@preconcurrency import TDLibKit
import Testing

// MARK: - PermissionsManagerTests

struct PermissionsManagerTests {
    @Test func `denied contacts permission does not fetch or sync`() async {
        let access = ContactsAccessMock(status: .denied)
        let sync = ContactsSyncMock()
        let manager = PermissionsManager(contactsAccess: access, contactsSync: sync)

        let didSync = await manager.requestAndSyncContacts()

        #expect(!didSync)
        #expect(access.fetchCount == 0)
        #expect(await sync.receivedContacts() == nil)
    }

    @Test func `undetermined permission requests access then syncs contacts`() async throws {
        let access = ContactsAccessMock(
            status: .notDetermined,
            requestResult: true,
            contacts: [
                DeviceContactRecord(
                    firstName: "Ada",
                    lastName: "Lovelace",
                    phoneNumbers: ["+40 700 000 001", "+40 700 000 002"],
                ),
            ],
        )
        let sync = ContactsSyncMock()
        let manager = PermissionsManager(contactsAccess: access, contactsSync: sync)

        let didSync = await manager.requestAndSyncContacts()

        #expect(didSync)
        #expect(access.requestCount == 1)
        #expect(access.fetchCount == 1)
        let received = try #require(await sync.receivedContacts())
        #expect(received.count == 2)
        #expect(received.map(\.phoneNumber) == ["+40 700 000 001", "+40 700 000 002"])
    }

    @Test func `contact conversion matches TDLib limits and skips nameless entries`() {
        let longName = String(repeating: "A", count: 70)
        let contacts = PermissionsManager.importedContacts(from: [
            DeviceContactRecord(firstName: "", lastName: "Ignored", phoneNumbers: ["1"]),
            DeviceContactRecord(firstName: longName, lastName: longName, phoneNumbers: ["2"]),
        ])

        #expect(contacts.count == 1)
        #expect(contacts[0].firstName.count == 64)
        #expect(contacts[0].lastName.count == 64)
        #expect(contacts[0].phoneNumber == "2")
    }
}

// MARK: - ContactsAccessMock

private final class ContactsAccessMock: ContactsAccess, @unchecked Sendable {
    // MARK: Lifecycle

    init(
        status: ContactsAuthorizationStatus,
        requestResult: Bool = false,
        contacts: [DeviceContactRecord] = [],
    ) {
        self.status = status
        self.requestResult = requestResult
        self.contacts = contacts
    }

    // MARK: Internal

    var fetchCount: Int {
        lock.withLock { storedFetchCount }
    }

    var requestCount: Int {
        lock.withLock { storedRequestCount }
    }

    func authorizationStatus() -> ContactsAuthorizationStatus {
        status
    }

    func requestAccess() -> Bool {
        lock.withLock { storedRequestCount += 1 }
        return requestResult
    }

    func fetchContacts() -> [DeviceContactRecord] {
        lock.withLock { storedFetchCount += 1 }
        return contacts
    }

    // MARK: Private

    private let lock = NSLock()
    private let status: ContactsAuthorizationStatus
    private let requestResult: Bool
    private let contacts: [DeviceContactRecord]
    private var storedFetchCount = 0
    private var storedRequestCount = 0
}

// MARK: - ContactsSyncMock

private actor ContactsSyncMock: TelegramContactsSyncing {
    // MARK: Internal

    func changeImportedContacts(contacts: [ImportedContact]?) -> ImportedContacts {
        self.contacts = contacts
        return ImportedContacts(importerCount: [], userIds: [])
    }

    func receivedContacts() -> [ImportedContact]? {
        contacts
    }

    // MARK: Private

    private var contacts: [ImportedContact]?
}
