// BetterTGMacApp.swift

import AppKit
import SwiftUI
import UserNotifications

// MARK: - BetterTGMacApp

@main struct BetterTGMacApp: App {
    // MARK: Internal

    var body: some Scene {
        Window("BetterTG", id: "main") {
            MacRootView(model: model)
                .frame(minWidth: 820, minHeight: 560)
                .background(MacWindowBridge(appDelegate: appDelegate))
                .task {
                    appDelegate.model = model
                    model.start()
                }
        }
        .defaultSize(width: 1100, height: 760)
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("Quit BetterTG") {
                    appDelegate.requestTermination()
                }
                .keyboardShortcut("q", modifiers: .command)
            }
        }

        Settings {
            TelegramStorageSettingsView(service: model.service)
                .frame(width: 480, height: 340)
        }

        MenuBarExtra("BetterTG", systemImage: "paperplane.fill") {
            MacMenuBarView(model: model, appDelegate: appDelegate)
        }
    }

    // MARK: Private

    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate
    @State private var model = MacSessionModel()
}

// MARK: - MacAppDelegate

@MainActor final class MacAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate,
UNUserNotificationCenterDelegate {
    // MARK: Internal

    weak var model: MacSessionModel?

    func applicationDidFinishLaunching(_: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        UNUserNotificationCenter.current().delegate = self
    }

    func applicationDidResignActive(_: Notification) {
        model?.saveCurrentDraft()
    }

    func application(
        _: NSApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data,
    ) {
        model?.didRegisterForRemoteNotifications(deviceToken: deviceToken)
    }

    func application(
        _: NSApplication,
        didFailToRegisterForRemoteNotificationsWithError error: any Swift.Error,
    ) {
        model?.didFailToRegisterForRemoteNotifications(error: error)
    }

    func application(_: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        Task { @MainActor [weak self] in
            await self?.model?.processRemoteNotification(userInfo: userInfo)
        }
    }

    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        guard !allowsImmediateTermination else { return .terminateNow }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Keep BetterTG running?"
        alert.informativeText = "BetterTG can remain in the menu bar and receive Telegram updates and notifications."
        alert.addButton(withTitle: "Keep in Menu Bar")
        alert.addButton(withTitle: "Quit Completely")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            moveToMenuBar()
            return .terminateCancel
        case .alertSecondButtonReturn:
            model?.stop()
            allowsImmediateTermination = true
            return .terminateNow
        default:
            return .terminateCancel
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        false
    }

    func windowShouldClose(_: NSWindow) -> Bool {
        guard !allowsImmediateTermination else { return true }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Close BetterTG?"
        alert.informativeText = "You can keep BetterTG in the menu bar to continue receiving Telegram updates and notifications."
        alert.addButton(withTitle: "Keep in Menu Bar")
        alert.addButton(withTitle: "Quit Completely")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            moveToMenuBar()
        case .alertSecondButtonReturn:
            quitCompletely()
        default:
            break
        }
        return false
    }

    func showMainWindow() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        if let window = NSApplication.shared.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            NSApplication.shared.sendAction(Selector(("showMainWindow:")), to: nil, from: nil)
        }
    }

    func moveToMenuBar() {
        for window in NSApplication.shared.windows where window.canBecomeMain {
            window.orderOut(nil)
        }
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    func quitCompletely() {
        model?.stop()
        allowsImmediateTermination = true
        NSApplication.shared.terminate(nil)
    }

    func requestTermination() {
        NSApplication.shared.terminate(nil)
    }

    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void,
    ) {
        let chatId: Int64? =
            if let rawChatId = response.notification.request.content.userInfo["chatId"] as? String,
            let parsedChatId = Int64(rawChatId) {
                parsedChatId
            } else {
                nil
            }
        completionHandler()
        Task { @MainActor [weak self] in
            self?.showMainWindow()
            if let chatId {
                self?.model?.activateChat(chatId)
            }
        }
    }

    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void,
    ) {
        completionHandler([.banner, .sound])
    }

    // MARK: Private

    private var allowsImmediateTermination = false
}

// MARK: - MacWindowBridge

private struct MacWindowBridge: NSViewRepresentable {
    let appDelegate: MacAppDelegate

    func makeNSView(context _: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ view: NSView, context _: Context) {
        DispatchQueue.main.async { [weak view, weak appDelegate] in
            guard let window = view?.window, window.delegate !== appDelegate else { return }
            window.delegate = appDelegate
        }
    }
}

// MARK: - MacMenuBarView

private struct MacMenuBarView: View {
    // MARK: Internal

    @Bindable var model: MacSessionModel

    let appDelegate: MacAppDelegate

    var body: some View {
        Text(model.authorizationStatus)

        Divider()

        Button("Open BetterTG") {
            appDelegate.showMainWindow()
            openWindow(id: "main")
        }

        Button("Quit") {
            appDelegate.requestTermination()
        }
    }

    // MARK: Private

    @Environment(\.openWindow) private var openWindow
}
