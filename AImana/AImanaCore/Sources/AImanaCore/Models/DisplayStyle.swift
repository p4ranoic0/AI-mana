import Foundation

/// Visual treatment for quota values, shared by the app and its widget.
public enum DisplayStyle: String, Codable, CaseIterable, Sendable, Identifiable {
    case bars
    case rings
    case numbers

    public var id: String { rawValue }

    public var title: String { title() }

    public func title(locale: Locale? = nil) -> String {
        switch self {
        case .bars: CoreStrings.text("Bars", locale: locale)
        case .rings: CoreStrings.text("Rings", locale: locale)
        case .numbers: CoreStrings.text("Numbers", locale: locale)
        }
    }
}
