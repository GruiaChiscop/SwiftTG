// TelegramOpenLinksPreference.swift

import Foundation
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Which browser non-Telegram links (anything `TelegramDeepLink.isTelegramLink` doesn't claim)
/// open in - matches Telegram-iOS's own "Open Links In" setting, minus the more niche browsers
/// (Yandex, Opera Mini/Touch, Firefox Focus, DuckDuckGo) it also lists. iOS-only: there's no
/// in-app browser or per-app external-browser choice to make on macOS.
enum TelegramOpenLinksPreference: String, CaseIterable, Identifiable {
    case inApp
    case safari
    case chrome
    case firefox
    case edge
    case brave

    // MARK: Internal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inApp: "In-App"
        case .safari: "Safari"
        case .chrome: "Chrome"
        case .firefox: "Firefox"
        case .edge: "Microsoft Edge"
        case .brave: "Brave"
        }
    }

    #if os(iOS)
    /// `false` for an external browser that isn't installed - only options `isAvailable` lets
    /// through should be offered as choices.
    var isAvailable: Bool {
        guard let detectionScheme, let url = URL(string: detectionScheme) else { return true }
        return UIApplication.shared.canOpenURL(url)
    }
    #endif

    /// The URL to actually open for this choice, or `nil` for `.inApp` (handled separately by
    /// presenting `SFSafariViewController`) or when the URL couldn't be rewritten for that browser.
    func externalURL(for url: URL) -> URL? {
        switch self {
        case .inApp:
            nil
        case .safari:
            rewritingScheme(of: url) { $0 == "https" ? "x-safari-https" : "x-safari-http" }
        case .chrome:
            rewritingScheme(of: url) { $0 == "https" ? "googlechromes" : "googlechrome" }
        case .edge:
            rewritingScheme(of: url) { $0 == "https" ? "microsoft-edge-https" : "microsoft-edge-http" }
        case .firefox:
            wrapping(url, prefix: "firefox://open-url?url=")
        case .brave:
            wrapping(url, prefix: "brave://open-url?url=")
        }
    }

    // MARK: Private

    private var detectionScheme: String? {
        switch self {
        case .inApp, .safari: nil
        case .chrome: "googlechrome://"
        case .firefox: "firefox://"
        case .edge: "microsoft-edge-https://"
        case .brave: "brave://"
        }
    }

    private func rewritingScheme(of url: URL, to newScheme: (String?) -> String) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return nil }
        components.scheme = newScheme(components.scheme)
        return components.url
    }

    /// Embeds the whole URL, including its own query string, as the value of another URL's query
    /// parameter - `.urlQueryAllowed` alone still permits `&`/`=`/`?`/`/` unescaped, which would
    /// let an inner query string bleed into the outer one, so this escapes those too.
    private func wrapping(_ url: URL, prefix: String) -> URL? {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=?/")
        guard let escaped = url.absoluteString.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: prefix + escaped)
    }
}

// MARK: - TelegramOpenLinksSettings

enum TelegramOpenLinksSettings {
    static let defaultsKey = "BetterTG.openLinksIn"

    static var preference: TelegramOpenLinksPreference {
        get {
            UserDefaults.standard.string(forKey: defaultsKey).flatMap(TelegramOpenLinksPreference.init) ?? .inApp
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
        }
    }
}

#if os(iOS)

// MARK: - TelegramOpenLinksSettingsView

struct TelegramOpenLinksSettingsView: View {
    var onSelect: (TelegramOpenLinksPreference) -> Void = { _ in }

    var body: some View {
        Form {
            Section {
                ForEach(TelegramOpenLinksPreference.allCases.filter(\.isAvailable)) { option in
                    Button {
                        preference = option
                        TelegramOpenLinksSettings.preference = option
                        onSelect(option)
                    } label: {
                        LabeledContent(option.title) {
                            if option == preference {
                                Image(systemName: "checkmark")
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(option == preference ? .isSelected : [])
                }
            } footer: {
                Text("Only browsers installed on this device are listed.")
            }
        }
        .navigationTitle("Open Links In")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Private

    @State private var preference = TelegramOpenLinksSettings.preference
}

#endif
