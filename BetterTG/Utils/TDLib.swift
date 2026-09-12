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

    func startTdLibUpdateHandler() {
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
            systemVersion: MainActor.assumeIsolated { UIDevice.current.systemVersion },
        ))

        nc.publisher(&cancellables, for: UIApplication.willTerminateNotification) { [weak self] _ in
            self?.session.close()
        }

        // The app-icon badge otherwise never updates on its own: nothing else calls
        // `setBadgeCount`, and the only thing that could set it - the `badge` field on an incoming
        // remote push - only lands when a push actually arrives, not when messages get read while
        // the app is open. `unreadUnmutedCount` (not `unreadCount`) matches the official app's own
        // badge, which excludes muted chats.
        session.unreadChatCountPublisher
            .compactMap { $0?.unreadUnmutedCount }
            .removeDuplicates()
            .sink { count in
                Task { try? await UNUserNotificationCenter.current().setBadgeCount(count) }
            }
            .store(in: &cancellables)
    }

    /// Re-applies the last known unread-chat count to the app-icon badge, bypassing the dedup
    /// above. A push delivered while this process wasn't running (backgrounded or killed) has its
    /// own `aps.badge` guess from the server applied straight to the Home Screen icon by iOS - a
    /// number that can drift from what TDLib actually knows locally, and which nothing here would
    /// otherwise correct until TDLib's own count next *changes*. Called on every foreground
    /// transition so the icon self-corrects promptly instead of only when a delta happens to fire.
    func refreshBadgeCount() {
        guard let count = session.currentUnreadChatCount?.unreadUnmutedCount else { return }
        Task { try? await UNUserNotificationCenter.current().setBadgeCount(count) }
    }

    // MARK: Private

    private var cancellables = Set<AnyCancellable>()
    private let session: TelegramSession
}
