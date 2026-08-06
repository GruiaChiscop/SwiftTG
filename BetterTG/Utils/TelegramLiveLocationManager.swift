// TelegramLiveLocationManager.swift

import CoreLocation
import Foundation
import TDLibKit

// MARK: - TelegramLiveShare

/// One outgoing live location this device is actively updating.
struct TelegramLiveShare: Identifiable {
    /// TDLib's sentinel for "share until manually stopped" on `LiveLocation.livePeriod`.
    static let indefiniteLivePeriod = 0x7FFF_FFFF

    let messageId: Int64
    let chatId: Int64
    let chatTitle: String
    let livePeriod: Int
    let expiresAt: Foundation.Date

    var id: Int64 { messageId }
    var isIndefinite: Bool { livePeriod == Self.indefiniteLivePeriod }
}

// MARK: - TelegramLiveLocationManager

/// Keeps every outgoing live location message updated with the device's real position - including
/// while backgrounded or locked, which is the entire point of "live" location - by driving a
/// single background-capable `CLLocationManager` and periodically calling
/// `editMessageLiveLocation` for each active share. iOS only: this is what macOS explicitly
/// doesn't get, since it doesn't move around with the user.
///
/// TDLib itself tracks which messages still need updates (`getActiveLiveLocationMessages`,
/// persisted across restarts via the message database), so this class doesn't need its own
/// persistence layer - `resumeActiveShares()` just asks TDLib on every launch.
@MainActor @Observable final class TelegramLiveLocationManager: NSObject, CLLocationManagerDelegate {
    // MARK: Internal

    static let shared = TelegramLiveLocationManager()

    private(set) var activeShares = [Int64: TelegramLiveShare]()

    /// Registers a share that was just sent - called right after the composer's send succeeds.
    func start(chatId: Int64, chatTitle: String, messageId: Int64, livePeriod: Int, expiresIn: Int) {
        activeShares[messageId] = TelegramLiveShare(
            messageId: messageId,
            chatId: chatId,
            chatTitle: chatTitle,
            livePeriod: livePeriod,
            expiresAt: Foundation.Date().addingTimeInterval(TimeInterval(expiresIn)),
        )
        armTrackingIfNeeded()
        rescheduleExpiryTimer()
    }

    /// User-initiated stop (the global banner's Stop button) - also called internally once a
    /// share's `expiresAt` passes. Best-effort on the network call: local tracking always stops
    /// either way, since TDLib may have already finalized an expired share server-side itself.
    func stop(messageId: Int64) async {
        guard let share = activeShares[messageId] else { return }
        activeShares.removeValue(forKey: messageId)
        lastSentAt.removeValue(forKey: messageId)
        if let edited = try? await TDLib.shared.service.editMessageLiveLocation(
            chatId: share.chatId,
            location: nil,
            messageId: messageId,
            replyMarkup: nil,
        ) {
            TDLib.shared.service.notifyMessageContentChanged(
                chatId: share.chatId,
                messageId: messageId,
                newContent: edited.content,
            )
        }
        teardownTrackingIfEmpty()
        rescheduleExpiryTimer()
    }

    /// Rebuilds `activeShares` from whatever TDLib still considers live - called once TDLib is
    /// ready, on every launch, so tracking resumes after the app was fully relaunched.
    func resumeActiveShares() async {
        guard let messages = try? await TDLib.shared.service.getActiveLiveLocationMessages().messages else { return }
        for message in messages {
            guard case .messageLiveLocation(let content) = message.content else { continue }
            let chatTitle = await (try? TDLib.shared.service.getChat(chatId: message.chatId))?.title ?? ""
            activeShares[message.id] = TelegramLiveShare(
                messageId: message.id,
                chatId: message.chatId,
                chatTitle: chatTitle,
                livePeriod: content.location.livePeriod,
                expiresAt: Foundation.Date().addingTimeInterval(TimeInterval(content.expiresIn)),
            )
        }
        armTrackingIfNeeded()
        rescheduleExpiryTimer()
    }

    nonisolated func locationManager(_: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            await self.handleLocationUpdate(location)
        }
    }

    // MARK: Private

    /// One edit call per active share at most this often - mirrors Telegram-iOS's own ~4s
    /// throttle on its live location updates.
    private static let minimumUpdateInterval: TimeInterval = 5

    @ObservationIgnored private lazy var locationManager: CLLocationManager = {
        let manager = CLLocationManager()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 20
        manager.activityType = .other
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        return manager
    }()

    @ObservationIgnored private var isTracking = false
    @ObservationIgnored private var lastSentAt = [Int64: Foundation.Date]()
    @ObservationIgnored private var expiryTask: Task<Void, Never>?

    private func armTrackingIfNeeded() {
        guard !activeShares.isEmpty, !isTracking else { return }
        isTracking = true
        locationManager.startUpdatingLocation()
    }

    private func teardownTrackingIfEmpty() {
        guard activeShares.isEmpty, isTracking else { return }
        isTracking = false
        locationManager.stopUpdatingLocation()
    }

    private func rescheduleExpiryTimer() {
        expiryTask?.cancel()
        guard let earliestExpiry = activeShares.values.map(\.expiresAt).min() else { return }
        let delay = earliestExpiry.timeIntervalSinceNow
        expiryTask = Task {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            await expireDueShares()
        }
    }

    private func expireDueShares() async {
        let now = Foundation.Date()
        let dueMessageIds = activeShares.values.filter { $0.expiresAt <= now }.map(\.messageId)
        for messageId in dueMessageIds {
            await stop(messageId: messageId)
        }
    }

    private func handleLocationUpdate(_ location: CLLocation) async {
        let now = Foundation.Date()
        let heading = location.course >= 0 ? Int(location.course.rounded()) : 0
        for (messageId, share) in activeShares {
            if let lastSent = lastSentAt[messageId], now.timeIntervalSince(lastSent) < Self.minimumUpdateInterval {
                continue
            }
            lastSentAt[messageId] = now
            if let edited = try? await TDLib.shared.service.editMessageLiveLocation(
                chatId: share.chatId,
                location: LiveLocation(
                    heading: heading,
                    livePeriod: share.livePeriod,
                    location: Location(
                        horizontalAccuracy: max(location.horizontalAccuracy, 0),
                        latitude: location.coordinate.latitude,
                        longitude: location.coordinate.longitude,
                    ),
                    proximityAlertRadius: 0,
                ),
                messageId: messageId,
                replyMarkup: nil,
            ) {
                TDLib.shared.service.notifyMessageContentChanged(
                    chatId: share.chatId,
                    messageId: messageId,
                    newContent: edited.content,
                )
            }
        }
    }
}
