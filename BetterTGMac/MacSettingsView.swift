// MacSettingsView.swift

import SwiftUI

// MARK: - MacSettingsSection

private enum MacSettingsSection: String, CaseIterable, Identifiable {
    case profile
    case proxy
    case activeSessions
    case chatFolders
    case notifications
    case privacy
    case dataAndStorage
    case appearance

    // MARK: Internal

    var id: Self { self }

    var title: String {
        switch self {
        case .profile: "Profile"
        case .proxy: "Proxy"
        case .activeSessions: "Devices"
        case .chatFolders: "Chat Folders"
        case .notifications: "Notifications and Sounds"
        case .privacy: "Privacy and Security"
        case .dataAndStorage: "Data and Storage"
        case .appearance: "Appearance"
        }
    }

    var systemImage: String {
        switch self {
        case .profile: "person.crop.circle"
        case .proxy: "network"
        case .activeSessions: "checkmark.shield"
        case .chatFolders: "folder"
        case .notifications: "bell"
        case .privacy: "hand.raised"
        case .dataAndStorage: "internaldrive"
        case .appearance: "paintpalette"
        }
    }
}

// MARK: - MacSettingsView

struct MacSettingsView: View {
    // MARK: Internal

    let service: any TelegramService

    var body: some View {
        NavigationSplitView {
            List(visibleSections, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(180)
        } detail: {
            switch selection ?? .profile {
            case .profile:
                EditProfileView(service: service)
            case .proxy:
                TelegramProxySettingsView(service: service)
            case .activeSessions:
                ActiveSessionsView(service: service)
            case .chatFolders:
                TelegramChatFoldersView(service: service)
            case .notifications:
                TelegramNotificationsView(service: service)
            case .privacy:
                TelegramPrivacyView(service: service)
            case .dataAndStorage:
                TelegramStorageSettingsView(service: service)
            case .appearance:
                TelegramAppearanceSettingsView()
            }
        }
        .task { await proxyStatusStore.refresh(service: service) }
        .onChange(of: proxyStatusStore.shortcutStatus) { _, status in
            if status == nil, selection == .proxy {
                selection = .profile
            }
        }
    }

    // MARK: Private

    @State private var selection: MacSettingsSection? = .profile

    private let proxyStatusStore = TelegramProxyStatusStore.shared

    private var visibleSections: [MacSettingsSection] {
        MacSettingsSection.allCases.filter { section in
            section != .proxy || proxyStatusStore.shortcutStatus != nil
        }
    }
}
