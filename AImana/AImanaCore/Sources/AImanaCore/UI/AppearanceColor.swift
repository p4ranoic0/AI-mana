#if canImport(SwiftUI)
import SwiftUI

public extension AppearanceAccent {
    var color: Color {
        switch self {
        case .blue: .blue
        case .teal: .teal
        case .orange: .orange
        case .pink: .pink
        case .purple: .purple
        case .green: .green
        }
    }
}

public extension AppearanceTheme {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
#endif
