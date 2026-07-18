// PushNotificationsManager.swift

import UIKit
import UserNotifications

@MainActor final class PushNotificationsManager {
    // MARK: Lifecycle

    private init(service: any TelegramService = TDLib.shared.service) {
        self.registration = TelegramApplePushRegistration(
            service: service,
            isAppSandbox: Self.isAppSandbox,
        )
    }

    // MARK: Internal

    static let shared = PushNotificationsManager()

    func start() {
        registration.start()
    }

    func requestAuthorization() async {
        let granted = await (try? notificationCenter.requestAuthorization(
            options: [.alert, .badge, .sound],
        )) == true
        guard granted else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    func didRegister(deviceToken: Data) {
        registration.didRegister(deviceToken: deviceToken)
    }

    func didFailToRegister(error: any Swift.Error) {
        print("APNs registration failed: \(error.localizedDescription)")
    }

    func process(userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        do {
            try await registration.process(userInfo: userInfo)
            return .newData
        } catch {
            print("TDLib push processing failed: \(error.localizedDescription)")
            return .failed
        }
    }

    // MARK: Private

    private static var isAppSandbox: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    private let notificationCenter = UNUserNotificationCenter.current()
    private let registration: TelegramApplePushRegistration
}
