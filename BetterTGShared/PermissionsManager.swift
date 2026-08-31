// PermissionsManager.swift

import Contacts
import CoreLocation
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

// MARK: - LocationAuthorizationStatus

enum LocationAuthorizationStatus: Sendable {
    case authorized
    case denied
    case notDetermined
}

// MARK: - LocationAccessError

enum LocationAccessError: Swift.Error, LocalizedError {
    case accessDenied
    case noLocationReturned

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            "Location access was denied. Turn it on in Settings to share your location."
        case .noLocationReturned:
            "Couldn't determine your location."
        }
    }
}

// MARK: - LocationAccess

protocol LocationAccess: Sendable {
    func authorizationStatus() -> LocationAuthorizationStatus
    func requestAccess() async -> Bool
    func requestCurrentLocation() async throws -> CLLocation
    /// Upgrades to "Always" access (needed for live location updates to keep going while
    /// backgrounded) - distinct from `requestAccess()`, which only ever asks for "When In Use".
    func hasAlwaysAuthorization() -> Bool
    func requestAlwaysAuthorization() async -> Bool
}

// MARK: - SystemLocationAccess

final class SystemLocationAccess: NSObject, LocationAccess, CLLocationManagerDelegate, @unchecked Sendable {
    // MARK: Lifecycle

    override init() {
        super.init()
        manager.delegate = self
    }

    // MARK: Internal

    func authorizationStatus() -> LocationAuthorizationStatus {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            .authorized
        case .notDetermined:
            .notDetermined
        case .denied, .restricted:
            .denied
        @unknown default:
            .denied
        }
    }

    /// No-ops (returning the current status) if the system already asked the user once - iOS/macOS
    /// only ever show the system permission prompt while status is `.notDetermined`. Queues the
    /// continuation rather than storing a single one, so a second caller racing the first (two UI
    /// actions both needing location around the same time) doesn't silently overwrite - and orphan
    /// forever - the first one's continuation.
    func requestAccess() async -> Bool {
        guard manager.authorizationStatus == .notDetermined else {
            return authorizationStatus() == .authorized
        }
        return await withCheckedContinuation { continuation in
            authorizationContinuations.append(continuation)
            if authorizationContinuations.count == 1 {
                manager.requestWhenInUseAuthorization()
            }
        }
    }

    /// One-shot fix via `CLLocationUpdate.liveUpdates()` (the modern async replacement for the
    /// old delegate-based `requestLocation()`) - takes the first update that actually carries a
    /// location and stops there, rather than continuously streaming updates.
    func requestCurrentLocation() async throws -> CLLocation {
        guard authorizationStatus() == .authorized else { throw LocationAccessError.accessDenied }
        for try await update in CLLocationUpdate.liveUpdates() {
            if let location = update.location {
                return location
            }
        }
        throw LocationAccessError.noLocationReturned
    }

    func hasAlwaysAuthorization() -> Bool {
        manager.authorizationStatus == .authorizedAlways
    }

    /// No-op (returning the current state) once denied/restricted - like `requestAccess()`, the
    /// system only ever shows a prompt while there's still somewhere to go (`.notDetermined` or,
    /// on iOS specifically, the "When In Use" -> "Always" upgrade from `.authorizedWhenInUse` -
    /// macOS's `CLAuthorizationStatus` has no separate "when in use" case to upgrade from).
    func requestAlwaysAuthorization() async -> Bool {
        guard hasAlwaysAuthorization() == false else { return true }
        var canPrompt = manager.authorizationStatus == .notDetermined
        #if os(iOS)
        canPrompt = canPrompt || manager.authorizationStatus == .authorizedWhenInUse
        #endif
        guard canPrompt else { return false }
        return await withCheckedContinuation { continuation in
            alwaysAuthorizationContinuations.append(continuation)
            if alwaysAuthorizationContinuations.count == 1 {
                manager.requestAlwaysAuthorization()
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager.authorizationStatus != .notDetermined else { return }
        let pendingAuthorization = authorizationContinuations
        authorizationContinuations.removeAll()
        let isAuthorized = authorizationStatus() == .authorized
        for continuation in pendingAuthorization {
            continuation.resume(returning: isAuthorized)
        }
        let pendingAlwaysAuthorization = alwaysAuthorizationContinuations
        alwaysAuthorizationContinuations.removeAll()
        let hasAlways = hasAlwaysAuthorization()
        for continuation in pendingAlwaysAuthorization {
            continuation.resume(returning: hasAlways)
        }
    }

    // MARK: Private

    private let manager = CLLocationManager()
    private var authorizationContinuations = [CheckedContinuation<Bool, Never>]()
    private var alwaysAuthorizationContinuations = [CheckedContinuation<Bool, Never>]()
}

// MARK: - PermissionsManager

final class PermissionsManager: Sendable {
    // MARK: Lifecycle

    init(
        contactsAccess: any ContactsAccess = SystemContactsAccess(),
        // `TDLib` (the global TDLib client singleton) only exists on iOS - macOS has no equivalent
        // singleton (each window owns its own `MacSessionModel.service` instead), and never
        // exercises `requestAndSyncContacts()`/device-contacts sync in the first place, so
        // `nil` there is both correct and never actually reached.
        contactsSync: (any TelegramContactsSyncing)? = {
            #if os(iOS)
            TDLib.shared.service
            #else
            nil
            #endif
        }(),
        locationAccess: any LocationAccess = SystemLocationAccess(),
    ) {
        self.contactsAccess = contactsAccess
        self.contactsSync = contactsSync
        self.locationAccess = locationAccess
    }

    // MARK: Internal

    static let shared = PermissionsManager()

    /// Safe to read on every render - `CNContactStore.authorizationStatus(for:)` is a cheap,
    /// synchronous system call, unlike expensive on-device work such as `NLLanguageRecognizer`.
    var contactsAuthorizationStatus: ContactsAuthorizationStatus {
        contactsAccess.authorizationStatus()
    }

    /// Safe to read on every render - same reasoning as `contactsAuthorizationStatus`.
    var locationAuthorizationStatus: LocationAuthorizationStatus {
        locationAccess.authorizationStatus()
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
    /// authorized - this never itself prompts, unlike `requestAndSyncContacts()`.
    func fetchDeviceContactsIfAuthorized() async -> [DeviceContactRecord] {
        guard contactsAuthorizationStatus == .authorized else { return [] }
        return await Self.fetchContactsConcurrently(access: contactsAccess) ?? []
    }

    @discardableResult func requestAndSyncContacts() async -> Bool {
        guard let contactsSync else { return false }
        guard await contactsAreAllowed() else { return false }
        guard let records = await Self.fetchContactsConcurrently(access: contactsAccess) else { return false }

        let contacts = Self.importedContacts(from: records)
        guard await (try? contactsSync.changeImportedContacts(contacts: contacts)) != nil else { return false }
        return true
    }

    /// Requests location access if not yet determined, then fetches a single current fix. Used by
    /// the location-sharing composer's "send my current location" flow.
    func requestCurrentLocation() async throws -> CLLocation {
        guard await locationIsAllowed() else { throw LocationAccessError.accessDenied }
        return try await locationAccess.requestCurrentLocation()
    }

    /// Upgrades to "Always" access, needed before starting live location sharing so updates keep
    /// going while the app is backgrounded. Returns `false` without throwing if the user declines
    /// or access is already permanently denied - the caller decides how to surface that.
    func requestAlwaysAuthorization() async -> Bool {
        await locationAccess.requestAlwaysAuthorization()
    }

    // MARK: Private

    private let contactsAccess: any ContactsAccess
    private let contactsSync: (any TelegramContactsSyncing)?
    private let locationAccess: any LocationAccess

    /// `@concurrent` (Swift 6.2) offloads this off the caller's context directly - unlike
    /// `Task.detached`, cancelling the caller's own task now actually propagates into the address
    /// book fetch below instead of only discarding its result afterward.
    @concurrent
    private static func fetchContactsConcurrently(access: any ContactsAccess) async -> [DeviceContactRecord]? {
        try? access.fetchContacts()
    }

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

    @MainActor private func locationIsAllowed() async -> Bool {
        switch locationAccess.authorizationStatus() {
        case .authorized:
            true
        case .denied:
            false
        case .notDetermined:
            await locationAccess.requestAccess()
        }
    }
}
