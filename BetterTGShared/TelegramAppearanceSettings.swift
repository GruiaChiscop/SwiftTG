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
    @AppStorage(TelegramAccentColor.defaultsKey) private var accentColorRawValue = TelegramAccentColor.blue.rawValue
    @AppStorage(TelegramColorSchemeOption.defaultsKey) private var colorSchemeRawValue = TelegramColorSchemeOption.system
        .rawValue

    func body(content: Content) -> some View {
        content
            .tint((TelegramAccentColor(rawValue: accentColorRawValue) ?? .blue).color)
            .preferredColorScheme((TelegramColorSchemeOption(rawValue: colorSchemeRawValue) ?? .system).colorScheme)
    }
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
        }
        .navigationTitle("Appearance")
    }

    // MARK: Private

    @AppStorage(TelegramAccentColor.defaultsKey) private var accentColorRawValue = TelegramAccentColor.blue.rawValue
    @AppStorage(TelegramColorSchemeOption.defaultsKey) private var colorSchemeRawValue = TelegramColorSchemeOption.system
        .rawValue
}
