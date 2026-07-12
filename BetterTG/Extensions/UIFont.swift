// UIFont.swift

import SwiftUI

extension UIFont {
    static var monospaced: UIFont {
        UIFontMetrics(forTextStyle: .body).scaledFont(
            for: UIFont(name: "Menlo", size: 17) ?? UIFont.monospacedSystemFont(ofSize: 17, weight: .regular),
        )
    }

    static var bold: UIFont {
        UIFontMetrics(forTextStyle: .body).scaledFont(for: UIFont.boldSystemFont(ofSize: 17))
    }

    static var italic: UIFont {
        UIFontMetrics(forTextStyle: .body).scaledFont(for: UIFont.italicSystemFont(ofSize: 17))
    }

    static var body: UIFont { UIFont.preferredFont(forTextStyle: .body) }
    static var caption: UIFont { UIFont.preferredFont(forTextStyle: .caption1) }
}
