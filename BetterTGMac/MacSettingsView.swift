// MacSettingsView.swift

import SwiftUI

// MARK: - MacSettingsSection

private enum MacSettingsSection: String, CaseIterable, Identifiable {
    case profile
    case blockedUsers
    case activeSessions
    case notifications
    case appearance
    case privacy
    case twoStepVerification
    case appLock
    case storage
    case proxy

    // MARK: Internal

    var id: Self { self }

    var title: String {
        switch self {
        case .profile: "Profile"
        case .blockedUsers: "Blocked Users"
        case .activeSessions: "Devices"
        case .notifications: "Notifications and Sounds"
        case .appearance: "Appearance"
        case .privacy: "Privacy"
        case .twoStepVerification: "Two-Step Verification"
        case .appLock: "App Lock"
        case .storage: "Storage"
        case .proxy: "Proxy"
        }
    }

    var systemImage: String {
        switch self {
        case .profile: "person.crop.circle"
        case .blockedUsers: "hand.raised.slash"
        case .activeSessions: "checkmark.shield"
        case .notifications: "bell"
        case .appearance: "paintpalette"
        case .privacy: "hand.raised"
        case .twoStepVerification: "lock.shield"
        case .appLock: "lock"
        case .storage: "internaldrive"
        case .proxy: "network"
        }
    }
}

// MARK: - MacSettingsView

struct MacSettingsView: View {
    // MARK: Internal

    let service: any TelegramService

    var body: some View {
        NavigationSplitView {
            List(MacSettingsSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(180)
        } detail: {
            switch selection ?? .profile {
            case .profile:
                EditProfileView(service: service)
            case .blockedUsers:
                BlockedUsersView(service: service)
            case .activeSessions:
                ActiveSessionsView(service: service)
            case .notifications:
                TelegramNotificationsView(service: service)
            case .appearance:
                TelegramAppearanceSettingsView()
            case .privacy:
                TelegramPrivacyView(service: service)
            case .twoStepVerification:
                TelegramTwoStepVerificationView(service: service)
            case .appLock:
                TelegramAppLockSettingsView()
            case .storage:
                TelegramStorageSettingsView(service: service)
            case .proxy:
                TelegramProxySettingsView(service: service)
            }
        }
    }

    // MARK: Private

    @State private var selection: MacSettingsSection? = .profile
}
