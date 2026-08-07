// TelegramAppearanceSettings.swift

import SwiftUI

// MARK: - TelegramColorSchemeOption

enum TelegramColorSchemeOption: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    // MARK: Internal

    static let defaultsKey = "BetterTG.appearance.colorScheme"

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    static func stored() -> Self {
        Self(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .system
    }
}

// MARK: - TelegramAccentColor

enum TelegramAccentColor: String, CaseIterable, Identifiable {
    case blue
    case red
    case orange
    case violet
    case green
    case cyan
    case pink

    // MARK: Internal

    static let defaultsKey = "BetterTG.appearance.accentColor"

    var id: Self { self }

    var title: String {
        switch self {
        case .blue: "Blue"
        case .red: "Red"
        case .orange: "Orange"
        case .violet: "Violet"
        case .green: "Green"
        case .cyan: "Cyan"
        case .pink: "Pink"
        }
    }

    var color: Color {
        switch self {
        case .blue: Color(red: 0.0, green: 0.478, blue: 1.0)
        case .red: Color(red: 0.937, green: 0.267, blue: 0.267)
        case .orange: Color(red: 1.0, green: 0.584, blue: 0.0)
        case .violet: Color(red: 0.549, green: 0.298, blue: 1.0)
        case .green: Color(red: 0.204, green: 0.780, blue: 0.349)
        case .cyan: Color(red: 0.196, green: 0.741, blue: 0.929)
        case .pink: Color(red: 1.0, green: 0.318, blue: 0.573)
        }
    }

    static func stored() -> Self {
        Self(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .blue
    }
}

// MARK: - TelegramMessageTextSize

enum TelegramMessageTextSize: String, CaseIterable, Identifiable {
    case small
    case medium
    case large
    case extraLarge
    case huge

    // MARK: Internal

    static let defaultsKey = "BetterTG.appearance.messageTextSize"

    var id: Self { self }

    var title: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        case .extraLarge: "Extra Large"
        case .huge: "Huge"
        }
    }

    var dynamicTypeSize: DynamicTypeSize {
        switch self {
        case .small: .small
        case .medium: .large
        case .large: .xLarge
        case .extraLarge: .xxLarge
        case .huge: .xxxLarge
        }
    }

    static func stored() -> Self {
        Self(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .medium
    }
}

// MARK: - TelegramBubbleCornerStyle

enum TelegramBubbleCornerStyle: String, CaseIterable, Identifiable {
    case rounded
    case minimal

    // MARK: Internal

    static let defaultsKey = "BetterTG.appearance.bubbleCorners"

    var id: Self { self }

    var title: String {
        switch self {
        case .rounded: "Rounded"
        case .minimal: "Minimal"
        }
    }

    /// Matches the radius `MessageView`/`MacMessageRow` already hard-coded before this setting
    /// existed.
    var radius: CGFloat {
        switch self {
        case .rounded: 20
        case .minimal: 8
        }
    }

    static func stored() -> Self {
        Self(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .rounded
    }
}

// MARK: - TelegramChatWallpaper

/// A curated palette rather than a free-form color picker, matching `TelegramAccentColor`'s own
/// fixed-preset approach - and, like accent color and color scheme, purely a local client
/// preference (not synced through TDLib's own chat-background system).
enum TelegramChatWallpaper: String, CaseIterable, Identifiable {
    case `default`
    case midnightBlue
    case charcoal
    case forest
    case sunset
    case ocean
    case dusk

    // MARK: Internal

    static let defaultsKey = "BetterTG.appearance.wallpaper"

    var id: Self { self }

    var title: String {
        switch self {
        case .default: "Default"
        case .midnightBlue: "Midnight Blue"
        case .charcoal: "Charcoal"
        case .forest: "Forest"
        case .sunset: "Sunset"
        case .ocean: "Ocean"
        case .dusk: "Dusk"
        }
    }

    @ViewBuilder var swatch: some View {
        switch self {
        case .default:
            Color.black
        case .midnightBlue:
            Color(red: 0.043, green: 0.055, blue: 0.184)
        case .charcoal:
            Color(red: 0.11, green: 0.11, blue: 0.12)
        case .forest:
            Color(red: 0.031, green: 0.129, blue: 0.078)
        case .sunset:
            LinearGradient(
                colors: [Color(red: 0.4, green: 0.09, blue: 0.19), Color(red: 0.85, green: 0.4, blue: 0.15)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing,
            )
        case .ocean:
            LinearGradient(
                colors: [Color(red: 0.02, green: 0.11, blue: 0.22), Color(red: 0.04, green: 0.35, blue: 0.42)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing,
            )
        case .dusk:
            LinearGradient(
                colors: [Color(red: 0.1, green: 0.05, blue: 0.25), Color(red: 0.35, green: 0.12, blue: 0.35)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing,
            )
        }
    }

    static func stored() -> Self {
        Self(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .default
    }
}

extension EnvironmentValues {
    // Read by `MessageView`/`MacMessageRow` - an `@Environment` read costs nothing per row, unlike
    // giving every message its own `@AppStorage` (message rows are a hot, perf-sensitive path; see
    // the doc comments throughout `MessageView.swift`/`MacMessageRow.swift`). `telegramAppearance()`
    // resolves the stored preference into this environment value exactly once, at the app root.
    @Entry var telegramBubbleCornerRadius: CGFloat = TelegramBubbleCornerStyle.rounded.radius
}

// MARK: - View + telegramMessageTextSize

extension View {
    /// Scopes the persisted message-text-size preference to a subtree (the message list) rather
    /// than the whole app, matching the official app's own "Text Size" setting - it resizes chat
    /// bubbles specifically, not every screen's text.
    func telegramMessageTextSize() -> some View {
        modifier(TelegramMessageTextSizeModifier())
    }
}

// MARK: - TelegramMessageTextSizeModifier

private struct TelegramMessageTextSizeModifier: ViewModifier {
    // MARK: Internal

    func body(content: Content) -> some View {
        content.dynamicTypeSize((TelegramMessageTextSize(rawValue: textSizeRawValue) ?? .medium).dynamicTypeSize)
    }

    // MARK: Private

    @AppStorage(TelegramMessageTextSize.defaultsKey) private var textSizeRawValue = TelegramMessageTextSize.medium
        .rawValue
}

// MARK: - View + telegramChatWallpaper

extension View {
    /// Scopes the persisted chat-wallpaper preference to a subtree (the message list background)
    /// rather than the whole app.
    func telegramChatWallpaper() -> some View {
        modifier(TelegramChatWallpaperModifier())
    }
}

// MARK: - TelegramChatWallpaperModifier

private struct TelegramChatWallpaperModifier: ViewModifier {
    // MARK: Internal

    func body(content: Content) -> some View {
        content.background((TelegramChatWallpaper(rawValue: wallpaperRawValue) ?? .default).swatch)
    }

    // MARK: Private

    @AppStorage(TelegramChatWallpaper.defaultsKey) private var wallpaperRawValue = TelegramChatWallpaper.default
        .rawValue
}

// MARK: - View + telegramAppearance

extension View {
    /// Applies the persisted appearance preferences. Reads live via `@AppStorage` so it stays in
    /// sync with `TelegramAppearanceSettingsView` without any extra plumbing.
    func telegramAppearance() -> some View {
        modifier(TelegramAppearanceModifier())
    }
}

// MARK: - TelegramAppearanceModifier

private struct TelegramAppearanceModifier: ViewModifier {
    // MARK: Internal

    func body(content: Content) -> some View {
        content
            .tint((TelegramAccentColor(rawValue: accentColorRawValue) ?? .blue).color)
            .preferredColorScheme((TelegramColorSchemeOption(rawValue: colorSchemeRawValue) ?? .system).colorScheme)
            .environment(
                \.telegramBubbleCornerRadius,
                (TelegramBubbleCornerStyle(rawValue: bubbleCornerStyleRawValue) ?? .rounded).radius,
            )
    }

    // MARK: Private

    @AppStorage(TelegramAccentColor.defaultsKey) private var accentColorRawValue = TelegramAccentColor.blue.rawValue
    @AppStorage(TelegramBubbleCornerStyle.defaultsKey) private var bubbleCornerStyleRawValue = TelegramBubbleCornerStyle
        .rounded.rawValue
    @AppStorage(TelegramColorSchemeOption.defaultsKey) private var colorSchemeRawValue = TelegramColorSchemeOption
        .system
        .rawValue
}

// MARK: - TelegramAppearanceSettingsView

struct TelegramAppearanceSettingsView: View {
    // MARK: Internal

    var body: some View {
        Form {
            Section("Color Scheme") {
                Picker("Color Scheme", selection: $colorSchemeRawValue) {
                    ForEach(TelegramColorSchemeOption.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Section("Accent Color") {
                ForEach(TelegramAccentColor.allCases) { option in
                    Button {
                        accentColorRawValue = option.rawValue
                    } label: {
                        HStack {
                            Circle()
                                .fill(option.color)
                                .frame(width: 20, height: 20)
                                .accessibilityHidden(true)
                            Text(option.title)
                                .foregroundStyle(.primary)
                            Spacer()
                            if accentColorRawValue == option.rawValue {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(accentColorRawValue == option.rawValue ? [.isSelected] : [])
                }
            }

            Section("Text Size") {
                Picker("Text Size", selection: $textSizeRawValue) {
                    ForEach(TelegramMessageTextSize.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                .labelsHidden()
            }

            Section("Bubble Corners") {
                Picker("Bubble Corners", selection: $bubbleCornerStyleRawValue) {
                    ForEach(TelegramBubbleCornerStyle.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Section("Chat Background") {
                ForEach(TelegramChatWallpaper.allCases) { option in
                    Button {
                        wallpaperRawValue = option.rawValue
                    } label: {
                        HStack {
                            option.swatch
                                .clipShape(Circle())
                                .frame(width: 20, height: 20)
                                .accessibilityHidden(true)
                            Text(option.title)
                                .foregroundStyle(.primary)
                            Spacer()
                            if wallpaperRawValue == option.rawValue {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(wallpaperRawValue == option.rawValue ? [.isSelected] : [])
                }
            }
        }
        .navigationTitle("Appearance")
    }

    // MARK: Private

    @AppStorage(TelegramAccentColor.defaultsKey) private var accentColorRawValue = TelegramAccentColor.blue.rawValue
    @AppStorage(TelegramBubbleCornerStyle.defaultsKey) private var bubbleCornerStyleRawValue = TelegramBubbleCornerStyle
        .rounded.rawValue
    @AppStorage(TelegramColorSchemeOption.defaultsKey) private var colorSchemeRawValue = TelegramColorSchemeOption
        .system
        .rawValue
    @AppStorage(TelegramMessageTextSize.defaultsKey) private var textSizeRawValue = TelegramMessageTextSize.medium
        .rawValue
    @AppStorage(TelegramChatWallpaper.defaultsKey) private var wallpaperRawValue = TelegramChatWallpaper.default
        .rawValue
}
