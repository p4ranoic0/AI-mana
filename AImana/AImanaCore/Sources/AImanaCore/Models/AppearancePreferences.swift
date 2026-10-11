import Foundation

public enum AppearanceTheme: String, CaseIterable, Sendable, Identifiable {
    case system, light, dark

    public var id: String { rawValue }
    public var title: String { CoreStrings.text(rawValue.capitalized) }
}

public enum AppearanceAccent: String, CaseIterable, Sendable, Identifiable {
    case blue, teal, orange, pink, purple, green

    public var id: String { rawValue }
    public var title: String { CoreStrings.text(rawValue.capitalized) }
}

public enum AppearancePreferences {
    public static let themeKey = "appearance.theme"
    public static let accentKey = "appearance.accent"

    public static var shared: UserDefaults {
        UserDefaults(suiteName: AppGroup.identifier) ?? .standard
    }

    public static func theme(defaults: UserDefaults = shared) -> AppearanceTheme {
        defaults.string(forKey: themeKey).flatMap(AppearanceTheme.init(rawValue:)) ?? .system
    }

    public static func setTheme(_ theme: AppearanceTheme, defaults: UserDefaults = shared) {
        defaults.set(theme.rawValue, forKey: themeKey)
    }

    public static func accent(defaults: UserDefaults = shared) -> AppearanceAccent {
        defaults.string(forKey: accentKey).flatMap(AppearanceAccent.init(rawValue:)) ?? .blue
    }

    public static func setAccent(_ accent: AppearanceAccent, defaults: UserDefaults = shared) {
        defaults.set(accent.rawValue, forKey: accentKey)
    }
}
