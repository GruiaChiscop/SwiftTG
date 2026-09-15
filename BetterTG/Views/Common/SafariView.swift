// SafariView.swift

import SafariServices
import SwiftUI

/// Presents a link in-app via `SFSafariViewController`, matching the "In-App" choice of the
/// "Open Links In" setting - Telegram-iOS's own equivalent screen, minus its reader/theming
/// extras, which `SFSafariViewController` doesn't expose.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context _: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_: SFSafariViewController, context _: Context) {}
}
