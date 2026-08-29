// CallOrientationController.swift

import UIKit

// MARK: - CallOrientationController

@MainActor enum CallOrientationController {
    // MARK: Internal

    static var supportedOrientations: UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return .all
        }
        return allowsLandscape ? .allButUpsideDown : .portrait
    }

    static func setAllowsLandscape(_ allowsLandscape: Bool) {
        guard self.allowsLandscape != allowsLandscape else { return }
        self.allowsLandscape = allowsLandscape

        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
            if !allowsLandscape, UIDevice.current.userInterfaceIdiom == .phone {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { error in
                    log("[Call] couldn't restore portrait orientation: \(error)")
                }
            }
        }
    }

    // MARK: Private

    private static var allowsLandscape = false
}
