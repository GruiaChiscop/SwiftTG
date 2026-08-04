// MacSettingsView.swift

import SwiftUI

// MARK: - MacSettingsSection

private enum MacSettingsSection: String, CaseIterable, Identifiable {
    case profile
    case blockedUsers
    case activeSessions
    case storage

    // MARK: Internal

    var id: Self { self }

    var title: String {
        switch self {
        case .profile: "Profile"
        case .blockedUsers: "Blocked Users"
        case .activeSessions: "Active Sessions"
        case .storage: "Storage"
        }
    }

    var systemImage: String {
        switch self {
        case .profile: "person.crop.circle"
        case .blockedUsers: "hand.raised.slash"
        case .activeSessions: "checkmark.shield"
        case .storage: "internaldrive"
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
            case .storage:
                TelegramStorageSettingsView(service: service)
            }
        }
    }

    // MARK: Private

    @State private var selection: MacSettingsSection? = .profile
}
