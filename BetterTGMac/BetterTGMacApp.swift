import AppKit
import SwiftUI
import UserNotifications

@main struct BetterTGMacApp: App {
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate
    @State private var model = MacSessionModel()

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
        .defaultSize(width: 1_100, height: 760)
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("Quit BetterTG") {
                    appDelegate.requestTermination()
                }
                .keyboardShortcut("q", modifiers: .command)
            }
        }

        MenuBarExtra("BetterTG", systemImage: "paperplane.fill") {
            MacMenuBarView(model: model, appDelegate: appDelegate)
        }
    }
}

@MainActor final class MacAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, UNUserNotificationCenterDelegate {
    weak var model: MacSessionModel?

    func applicationDidFinishLaunching(_: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        UNUserNotificationCenter.current().delegate = self
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
        let chatId: Int64?
        if let rawChatId = response.notification.request.content.userInfo["chatId"] as? String,
           let parsedChatId = Int64(rawChatId)
        {
            chatId = parsedChatId
        } else {
            chatId = nil
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

    private var allowsImmediateTermination = false
}

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

private struct MacMenuBarView: View {
    @Environment(\.openWindow) private var openWindow
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
}
