// TDLib.swift

import Combine
import SwiftUI
import TDLibKit
import UserNotifications

// MARK: - TDLib

final class TDLib: @unchecked Sendable {
    // MARK: Lifecycle

    private init() {
        self.session = TelegramSession()
    }

    // MARK: Internal

    static let shared = TDLib()

    var authorizationStatePublisher: AnyPublisher<AuthorizationState, Never> {
        session.authorizationStatePublisher
    }

    var service: any TelegramService { session }

    @MainActor func startTdLibUpdateHandler() {
        let dir = try? FileManager.default
            .url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "td")
            .path()
        guard let dir else { return }
        session.start(configuration: .init(
            apiHash: Secret.apiHash,
            apiId: Secret.apiId,
            applicationVersion: Utils.applicationVersion,
            databaseDirectory: dir,
            deviceModel: Utils.modelName,
            systemLanguageCode: "en-US",
            systemVersion: UIDevice.current.systemVersion,
        ))

        nc.publisher(&cancellables, for: UIApplication.willTerminateNotification) { [weak self] _ in
            self?.session.close()
        }

        // Matches Telegram-iOS's own Settings > Notifications > "Badge Counter" choice between
        // unread chats and unread messages (see TelegramBadgeCountPreference), both excluding
        // muted chats. Both of TDLib's counters for the main list are authoritative live counters;
        // unlike an APNs `badge`, they also advance immediately when messages are read in-app.
        // Combining both publishers (rather than switching subscriptions on preference change)
        // means flipping the setting re-applies whichever counter TDLib already has current, live,
        // with no stale-cache gap to worry about.
        Publishers.CombineLatest3(
            TelegramBadgeCountPreference.stylePublisher,
            session.unreadChatCountPublisher.compactMap { $0?.unreadUnmutedCount },
            session.unreadMessageCountPublisher.compactMap { $0?.unreadUnmutedCount },
        )
        .map { style, chatCount, messageCount in
            style == .chats ? chatCount : messageCount
        }
        .removeDuplicates()
        .sink { count in
            Task { try? await UNUserNotificationCenter.current().setBadgeCount(count) }
        }
        .store(in: &cancellables)
    }

    // MARK: Private

    private var cancellables = Set<AnyCancellable>()
    private let session: TelegramSession
}
