// PostLoginPermissionsView.swift

import SwiftUI
import UIKit
import UserNotifications

struct PostLoginPermissionsView: View {
    // MARK: Internal

    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "hand.raised.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text("Choose What to Enable")
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)

                    Text(
                        "Both options are optional. SwiftTG works even if you skip them, and you can change them later in Settings.",
                    )
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                }

                PermissionOnboardingRow(
                    systemImage: "bell.badge.fill",
                    title: "Notifications",
                    detail: "Allow alerts for new messages and calls when SwiftTG isn't open.",
                    actionTitle: notificationsActionTitle,
                    isEnabled: notificationsEnabled,
                    isWorking: isRequestingNotifications,
                    action: handleNotificationsAction,
                )

                PermissionOnboardingRow(
                    systemImage: "person.crop.circle.badge.checkmark",
                    title: "Sync Contacts",
                    detail: "If you choose to sync, SwiftTG sends names and phone numbers from your address book to Telegram so it can find people you know.",
                    actionTitle: contactsActionTitle,
                    isEnabled: contactsEnabled,
                    isWorking: isRequestingContacts,
                    action: handleContactsAction,
                )
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) {
            Button("Continue", action: onContinue)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .padding()
                .background(.bar)
                .disabled(isRequestingContacts || isRequestingNotifications)
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .task {
            await refreshStatuses()
        }
        .alert("Couldn't Enable Notifications", isPresented: $showsNotificationError) {
            Button("OK") {}
        } message: {
            Text("Please try again. If the problem continues, you can manage notifications in the Settings app.")
        }
        .alert("Couldn't Sync Contacts", isPresented: $showsContactsError) {
            Button("OK") {}
        } message: {
            Text("SwiftTG couldn't send your contacts to Telegram. Please check your connection and try again.")
        }
    }

    // MARK: Private

    @Environment(\.openURL) private var openURL
    @State private var contactsDenied = false
    @State private var contactsEnabled = false
    @State private var isRequestingContacts = false
    @State private var isRequestingNotifications = false
    @State private var notificationsDenied = false
    @State private var notificationsEnabled = false
    @State private var showsContactsError = false
    @State private var showsNotificationError = false

    private var contactsActionTitle: String {
        contactsDenied ? "Open Settings" : "Sync Contacts"
    }

    private var notificationsActionTitle: String {
        notificationsDenied ? "Open Settings" : "Enable Notifications"
    }

    private static func notificationsAreEnabled(for status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .ephemeral, .provisional:
            true
        case .denied, .notDetermined:
            false
        @unknown default:
            false
        }
    }

    private func handleNotificationsAction() {
        if notificationsDenied {
            openSystemSettings()
        } else {
            Task { await requestNotifications() }
        }
    }

    private func handleContactsAction() {
        if contactsDenied {
            openSystemSettings()
        } else {
            Task { await requestContacts() }
        }
    }

    @MainActor private func refreshStatuses() async {
        let notificationStatus = await PushNotificationsManager.shared.authorizationStatus()
        notificationsEnabled = Self.notificationsAreEnabled(for: notificationStatus)
        notificationsDenied = notificationStatus == .denied

        let contactsStatus = PermissionsManager.shared.contactsAuthorizationStatus
        contactsEnabled = contactsStatus == .authorized && TelegramContactsSyncPreference.isEnabled
        contactsDenied = contactsStatus == .denied
    }

    @MainActor private func requestNotifications() async {
        isRequestingNotifications = true
        defer { isRequestingNotifications = false }
        notificationsEnabled = await PushNotificationsManager.shared.requestAuthorization()
        let status = await PushNotificationsManager.shared.authorizationStatus()
        notificationsDenied = !notificationsEnabled && status == .denied
        showsNotificationError = !notificationsEnabled && !notificationsDenied
    }

    @MainActor private func requestContacts() async {
        isRequestingContacts = true
        defer { isRequestingContacts = false }
        let didSync = await PermissionsManager.shared.requestAndSyncContacts()
        TelegramContactsSyncPreference.isEnabled = didSync
        contactsEnabled = didSync
        contactsDenied = !didSync && PermissionsManager.shared.contactsAuthorizationStatus == .denied
        showsContactsError = !didSync && !contactsDenied
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}
