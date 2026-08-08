// BetterTGApp.swift

import AVKit
import SwiftUI
import TDLibKit
import UserNotifications

// MARK: - BetterTGApp

@main struct BetterTGApp: App {
    // MARK: Lifecycle

    init() {
        guard !Utils.isRunningTests else { return }
        TDLib.shared.startTdLibUpdateHandler()

        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
//        UINavigationBar.appearance().compactAppearance = appearance
//        UINavigationBar.appearance().standardAppearance = appearance
//        UINavigationBar.appearance().compactScrollEdgeAppearance = appearance
    }

    // MARK: Internal

    @UIApplicationDelegateAdaptor var delegate: AppDelegate

    var body: some Scene {
        WindowGroup {
            // The test bundle needs BetterTG.app as its host process just to link against the
            // app's own symbols (see `Utils.isRunningTests`) - it never wants the real app to
            // actually run, which would otherwise stand up a live TDLib client via `RootVM.shared`.
            if Utils.isRunningTests {
                EmptyView()
            } else {
                RootView()
                    .telegramAppearance()
                    .appLockOverlay()
                    // Handles both the Share Extension's `swifttg://share?id=<uuid>` hand-off
                    // (covers both a cold launch and an already-running app, unlike the
                    // hand-rolled `UIWindowSceneDelegate` this replaced, which turned out to never
                    // actually get invoked in practice) and any `tg:`/`t.me` deep link the app is
                    // opened with directly (a share-sheet "Open in SwiftTG", a Shortcut, etc.).
                    .onOpenURL { url in
                        if url.scheme == "swifttg" {
                            RootVM.shared.handleShareURL(url)
                        } else {
                            RootVM.shared.handleDeepLink(url)
                        }
                    }
            }
        }
        // Belt-and-suspenders for the share hand-off: `.authorizationStateReady` (RootVM's other
        // trigger for processPendingShareRequests) only fires once per TDLib session, the first
        // time it authenticates - if the app was merely backgrounded (not force-quit) between two
        // shares, it never fires again, so a share made while backgrounded would sit unprocessed
        // until the next real cold launch. Retrying on every foreground transition closes that gap
        // regardless of whether the extension's own `open(url:)` hand-off actually landed.
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                TelegramAppLockController.shared.noteWillEnterForeground()
                Task { await RootVM.shared.processPendingShareRequests() }
            case .background:
                TelegramAppLockController.shared.noteDidEnterBackground()
            case .inactive:
                break
            @unknown default:
                break
            }
        }
    }

    // MARK: Private

    @Environment(\.scenePhase) private var scenePhase
}

// MARK: - AppDelegate

@MainActor final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    // MARK: Internal

    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil,
    ) -> Bool {
        guard !Utils.isRunningTests else { return true }
        UNUserNotificationCenter.current().delegate = self
        Self.registerNotificationCategories()
        PushNotificationsManager.shared.start()
        return true
    }

    func application(
        _: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data,
    ) {
        PushNotificationsManager.shared.didRegister(deviceToken: deviceToken)
    }

    func application(
        _: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: any Swift.Error,
    ) {
        PushNotificationsManager.shared.didFailToRegister(error: error)
    }

    func application(
        _: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void,
    ) {
        Task { @MainActor in
            let result = await PushNotificationsManager.shared.process(userInfo: userInfo)
            completionHandler(result)
        }
    }

    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void,
    ) {
        completionHandler([.banner, .list, .sound, .badge])
        nonisolated(unsafe) let userInfo = notification.request.content.userInfo
        Task { @MainActor in
            _ = await PushNotificationsManager.shared.process(userInfo: userInfo)
        }
    }

    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void,
    ) {
        let content = response.notification.request.content
        var userInfo = content.userInfo
        if !content.threadIdentifier.isEmpty {
            userInfo["thread-id"] = content.threadIdentifier
        }
        nonisolated(unsafe) let capturedUserInfo = userInfo
        nonisolated(unsafe) let capturedResponse = response
        nonisolated(unsafe) let capturedCompletionHandler = completionHandler
        Task { @MainActor in
            let userInfo = capturedUserInfo
            let response = capturedResponse
            _ = await PushNotificationsManager.shared.process(userInfo: userInfo)
            if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
                await RootVM.shared.openChatFromNotification(userInfo: userInfo)
            } else if response.actionIdentifier == Self.replyActionIdentifier,
                      let textResponse = response as? UNTextInputNotificationResponse,
                      !textResponse.userText.isEmpty
            {
                await Self.sendReply(text: textResponse.userText, userInfo: userInfo)
            }
            capturedCompletionHandler()
        }
    }

    func application(
        _: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options _: UIScene.ConnectionOptions,
    ) -> UISceneConfiguration {
        let sceneConfig = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        sceneConfig.delegateClass = SceneDelegate.self
        return sceneConfig
    }

    // MARK: Private

    /// The action identifier within each repliable category below - Telegram's own push payload
    /// already stamps `aps.category` with one of `repliableCategoryIdentifiers` directly (confirmed
    /// by inspecting a real payload), matching the exact identifiers Telegram-iOS itself registers
    /// in its own `AppDelegate.swift`. No Notification Service Extension is needed: we just need to
    /// register actions under the same category identifiers Telegram already sends.
    private static let replyActionIdentifier = "reply"

    /// "r" - private text message, "m" - private media, "gr" - group text, "gm" - group media.
    /// Telegram-iOS also has "c" (channel) and "t" (reaction), left unregistered here since those
    /// aren't repliable and an unregistered category identifier just shows a plain notification.
    private static let repliableCategoryIdentifiers = ["r", "m", "gr", "gm"]

    private static func registerNotificationCategories() {
        let reply = UNTextInputNotificationAction(
            identifier: replyActionIdentifier,
            title: "Reply",
            options: [],
            textInputButtonTitle: "Send",
            textInputPlaceholder: "Message",
        )
        let categories = repliableCategoryIdentifiers.map { identifier in
            UNNotificationCategory(
                identifier: identifier,
                actions: [reply],
                intentIdentifiers: [],
                options: [],
            )
        }
        UNUserNotificationCenter.current().setNotificationCategories(Set(categories))
    }

    /// Mirrors Telegram-iOS's own reply-from-notification flow: mark the message read as a side
    /// effect of replying (there's no separate "Mark as Read" action, matching the real app), then
    /// send the typed text as a plain message.
    @MainActor private static func sendReply(text: String, userInfo: [AnyHashable: Any]) async {
        guard let target = TelegramNotificationPayload.target(from: userInfo),
              let customChat = await RootVM.shared.customChat(for: target)
        else { return }

        let service = RootVM.shared.service
        if let messageId = target.messageId {
            _ = try? await service.viewMessages(
                chatId: customChat.chat.id,
                forceRead: true,
                messageIds: [messageId],
                source: .messageSourceChatHistory,
            )
        }

        _ = try? await TelegramMessageSending.send(
            service: service,
            chatId: customChat.chat.id,
            contents: [TelegramMessageSending.textContent(FormattedText(entities: [], text: text))],
            replyTo: nil,
        )
    }
}

// MARK: - SceneDelegate

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(
        _ scene: UIScene,
        willConnectTo _: UISceneSession,
        options _: UIScene.ConnectionOptions,
    ) {
        guard let scene = scene as? UIWindowScene else { return }
        Utils.screen = scene.screen
    }
}
