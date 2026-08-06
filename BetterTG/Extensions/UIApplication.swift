// UIApplication.swift

import SwiftUI

extension UIApplication {
    static var safeAreaInsets: EdgeInsets { currentKeyWindow?.safeAreaInsets.swiftUIInsets ?? .init() }
    static var currentKeyWindow: UIWindow? {
        UIApplication.shared
            .connectedScenes
            .filter { $0.activationState == .foregroundActive }
            .map { $0 as? UIWindowScene }
            .compactMap(\.self)
            .first?
            .windows
            .filter(\.isKeyWindow)
            .first
    }
}

@MainActor func showShareSheet(_ items: [Any]) {
    guard let rootVC = UIApplication.currentKeyWindow?.rootViewController else { return }
    let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
    vc.isModalInPresentation = false
    if let presentedVC = rootVC.presentedViewController {
        presentedVC.present(vc, animated: true)
    } else {
        rootVC.present(vc, animated: true)
    }
}

@MainActor func showDocumentExporter(_ url: URL) {
    guard let rootViewController = UIApplication.currentKeyWindow?.rootViewController else { return }
    var presentingViewController = rootViewController
    while let presentedViewController = presentingViewController.presentedViewController {
        presentingViewController = presentedViewController
    }

    let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
    picker.shouldShowFileExtensions = true
    presentingViewController.present(picker, animated: true)
}
