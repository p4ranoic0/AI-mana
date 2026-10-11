#if canImport(SwiftUI)
import SwiftUI

public enum SoftTheme {
    public static let cream = Color(red: 251 / 255, green: 246 / 255, blue: 238 / 255)
    public static let ink = Color(red: 14 / 255, green: 15 / 255, blue: 19 / 255)
    public static let peach = Color(red: 246 / 255, green: 201 / 255, blue: 168 / 255)
    public static let pink = Color(red: 245 / 255, green: 184 / 255, blue: 219 / 255)
    public static let blue = Color(red: 182 / 255, green: 202 / 255, blue: 235 / 255)
    public static let olive = Color(red: 154 / 255, green: 171 / 255, blue: 99 / 255)
    public static let yellow = Color(red: 245 / 255, green: 216 / 255, blue: 103 / 255)
    /// Balance-only API providers: quiet tones that stay apart from the five lane colours above.
    public static let lavender = Color(red: 196 / 255, green: 186 / 255, blue: 240 / 255)
    public static let mint = Color(red: 160 / 255, green: 216 / 255, blue: 196 / 255)
    public static let slate = Color(red: 176 / 255, green: 184 / 255, blue: 196 / 255)
    /// GitHub Copilot: a soft sage, apart from Codex's olive and Moonshot's mint.
    public static let sage = Color(red: 196 / 255, green: 214 / 255, blue: 172 / 255)
    public static let cardRadius: CGFloat = 28
    public static let innerRadius: CGFloat = 16
    public static let cardPadding: CGFloat = 20

    /// Text contrast stays readable on cream while progress fills keep their vivid severity tint.
    public static func statusTextColor(_ severity: UsageSeverity, scheme: ColorScheme) -> Color {
        if scheme == .dark { return severity.tint }
        return switch severity {
        case .normal: Color(red: 0.05, green: 0.40, blue: 0.18)
        case .warning: Color(red: 0.53, green: 0.27, blue: 0.02)
        case .critical: Color(red: 0.65, green: 0.08, blue: 0.12)
        }
    }

    public enum Space {
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 16
        public static let xl: CGFloat = 24
        public static let xxl: CGFloat = 32
    }

    public enum TextStyle {
        case hero, title, headline, body, caption

        fileprivate var size: CGFloat {
            switch self {
            case .hero: 56
            case .title: 28
            case .headline: 20
            case .body: 15
            case .caption: 13
            }
        }

        fileprivate var weight: Font.Weight {
            switch self {
            case .hero, .title: .bold
            case .headline: .semibold
            case .body, .caption: .regular
            }
        }
    }

    public static func canvas(_ scheme: ColorScheme) -> Color { scheme == .dark ? ink : cream }

    private static func extraProviderIndex(_ id: String) -> Int? {
        let ids = (Bundle.main.object(forInfoDictionaryKey: "AImanaExtraProviderIDs") as? String ?? "")
            .split(separator: ",").map(String.init)
        return ids.firstIndex(of: id)
    }

    public static func laneTint(providerID: String, kind: UsageWindow.Kind) -> Color {
        if let index = extraProviderIndex(providerID) {
            if index == 0 { return slate }
            switch kind {
            case .session, .modelSession: return mint
            default: return blue
            }
        }
        return switch (providerID, kind) {
        case ("claude", .session): peach
        case ("claude", .weekly): pink
        case ("codex", .session): blue
        case ("codex", .weekly): olive
        case ("openrouter", .spendLimit): yellow
        case ("openrouter", .freeRequests): pink
        case ("copilot", .spendLimit): sage
        default: yellow
        }
    }

    public static func providerTint(_ providerID: String) -> Color {
        if let index = extraProviderIndex(providerID) { return index == 0 ? slate : mint }
        return switch providerID {
        case "claude": peach
        case "codex": blue
        case "openrouter": yellow
        case "deepseek": lavender
        case "moonshot": mint
        case "xai": slate
        case "copilot": sage
        default: olive
        }
    }

    public static func providerSymbol(_ providerID: String) -> String {
        if let index = extraProviderIndex(providerID) { return index == 0 ? "bolt" : "arrow.up.circle" }
        return switch providerID {
        case "claude": "sparkle"
        case "codex": "chevron.left.forwardslash.chevron.right"
        case "openrouter": "arrow.triangle.branch"
        case "deepseek": "fish"
        case "moonshot": "moon.stars"
        case "xai": "x.squareroot"
        case "copilot": "airplane"
        default: "cpu"
        }
    }

    public static func windowSymbol(_ kind: UsageWindow.Kind) -> String {
        switch kind {
        case .session: "timer"
        case .weekly, .monthly: "calendar"
        case .model, .modelSession: "cpu"
        case .spendLimit: "dollarsign.circle"
        case .freeRequests: "gift"
        }
    }
}

public extension View {
    func softSurface(tint: Color = .clear, radius: CGFloat = SoftTheme.cardRadius) -> some View {
        modifier(SoftSurfaceModifier(tint: tint, radius: radius))
    }

    func softText(_ style: SoftTheme.TextStyle) -> some View {
        modifier(SoftTextModifier(style: style))
    }
}

private struct SoftTextModifier: ViewModifier {
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1
    let style: SoftTheme.TextStyle

    func body(content: Content) -> some View {
        content.font(.system(size: style.size * scale, weight: style.weight, design: .rounded))
    }
}

public struct SoftIconBadge: View {
    @Environment(\.colorScheme) private var scheme
    public let symbol: String
    public let tint: Color
    public let size: CGFloat

    public init(_ symbol: String, tint: Color, size: CGFloat = 32) {
        self.symbol = symbol
        self.tint = tint
        self.size = size
    }

    public var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.46, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(scheme == .dark ? SoftTheme.cream : SoftTheme.ink)
            .frame(width: size, height: size)
            .background(tint.opacity(0.30), in: Circle())
            .accessibilityHidden(true)
    }
}

private struct SoftSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    let tint: Color
    let radius: CGFloat

    @ViewBuilder func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if #available(iOS 26.0, macOS 26.0, watchOS 26.0, *) {
            GlassEffectContainer {
                content
                    .background(tint.opacity(scheme == .dark ? 0.18 : 0.22), in: shape)
                    .glassEffect(.regular, in: shape)
                    .overlay(shape.strokeBorder(.primary.opacity(0.07), lineWidth: 0.5))
            }
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .background(tint.opacity(scheme == .dark ? 0.18 : 0.22), in: shape)
                .overlay(shape.strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
        }
    }
}

/// The app's name with "AI" in the icon's coral. In SF the capital I and a lowercase l are the same stroke, so a
/// plain "AImana" reads as "Almana"; the colour split keeps "AI" visibly its own word.
public struct BrandWordmark: View {
    public static let coral = Color(red: 240 / 255, green: 126 / 255, blue: 103 / 255)
    private let font: Font

    public init(font: Font = .system(.headline, design: .rounded, weight: .bold)) {
        self.font = font
    }

    public var body: some View {
        (Text(verbatim: "AI").foregroundStyle(Self.coral) + Text(verbatim: "mana"))
            .font(font)
            .accessibilityLabel(Text(verbatim: "AImana"))
    }
}
#endif
