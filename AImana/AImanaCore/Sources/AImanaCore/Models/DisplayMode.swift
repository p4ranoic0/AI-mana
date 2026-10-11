import Foundation

/// Whether the UI headlines how much was spent or how much is left. Shared by the app and the widget.
public enum DisplayMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case used
    case remaining

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .used: CoreStrings.text("Used")
        case .remaining: CoreStrings.text("Remaining")
        }
    }

    public var caption: String { CoreStrings.text(rawValue) }

    /// 0...100 value to show for this mode.
    public func percent(for window: UsageWindow) -> Double {
        switch self {
        case .used: window.displayUsedPercent
        case .remaining: window.remainingPercent
        }
    }
}

/// How worried to look. Always derived from what is *left*, whichever mode is displayed.
public enum UsageSeverity: Sendable, Equatable {
    case normal, warning, critical

    public init(remainingPercent: Double) {
        switch remainingPercent {
        case ..<10: self = .critical
        case ..<20: self = .warning
        default: self = .normal
        }
    }
}

public enum DisplayPreferences {
    public static let modeKey = "display.mode"
    public static let styleKey = "display.style"

    /// App Group defaults so the widget sees the choice made in the app.
    public static var shared: UserDefaults {
        UserDefaults(suiteName: AppGroup.identifier) ?? .standard
    }

    public static func mode(defaults: UserDefaults = shared) -> DisplayMode {
        defaults.string(forKey: modeKey).flatMap(DisplayMode.init(rawValue:)) ?? .used
    }

    public static func setMode(_ mode: DisplayMode, defaults: UserDefaults = shared) {
        defaults.set(mode.rawValue, forKey: modeKey)
    }

    public static func style(defaults: UserDefaults = shared) -> DisplayStyle {
        defaults.string(forKey: styleKey).flatMap(DisplayStyle.init(rawValue:)) ?? .bars
    }

    public static func setStyle(_ style: DisplayStyle, defaults: UserDefaults = shared) {
        defaults.set(style.rawValue, forKey: styleKey)
    }
}
