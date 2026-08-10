// TelegramEditorColor.swift

import SwiftUI

struct TelegramEditorColor: Equatable, Sendable {
    // MARK: Lifecycle

    init(red: Double, green: Double, blue: Double, opacity: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }

    init(_ color: Color) {
        let resolved = color.resolve(in: .init())
        self.red = Double(resolved.red)
        self.green = Double(resolved.green)
        self.blue = Double(resolved.blue)
        self.opacity = Double(resolved.opacity)
    }

    // MARK: Internal

    static let white = TelegramEditorColor(red: 1, green: 1, blue: 1, opacity: 1)

    var red: Double
    var green: Double
    var blue: Double
    var opacity: Double

    var color: Color {
        Color(red: red, green: green, blue: blue, opacity: opacity)
    }
}
