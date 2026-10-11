#if canImport(SwiftUI)
import SwiftUI

/// One-line pace summary: icon + coloured state word + the rest in secondary text. Never colour-only.
public struct PaceLine: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    public let pace: UsagePace
    public let now: Date
    public let compact: Bool

    public init(pace: UsagePace, now: Date = Date(), compact: Bool = false) {
        self.pace = pace
        self.now = now
        self.compact = compact
    }

    private var tint: Color {
        let severity: UsageSeverity = switch pace.status {
        case .comfortable, .tooEarly: .normal
        case .fast: .warning
        case .depleted: .critical
        }
        return SoftTheme.statusTextColor(severity, scheme: scheme)
    }

    private var symbol: String {
        switch pace.status {
        case .comfortable, .tooEarly: "checkmark"
        case .fast: "exclamationmark.triangle.fill"
        case .depleted: "minus.circle.fill"
        }
    }

    public var body: some View {
        if let text = UsageFormatter.paceText(pace, now: now, compact: compact) {
            let parts = text.components(separatedBy: " · ")
            HStack(alignment: .firstTextBaseline, spacing: SoftTheme.Space.xs) {
                Image(systemName: symbol).softText(.caption).fontWeight(.medium).foregroundStyle(tint)
                    .symbolRenderingMode(.hierarchical)
                    // Pulses twice, then rests: an endless pulse keeps the screen redrawing and costs battery.
                    .symbolEffect(.pulse, options: .repeat(2), isActive: pace.status == .fast && !reduceMotion)
                    .accessibilityHidden(true)
                Text(parts[0]).softText(.caption).fontWeight(.semibold).foregroundStyle(tint)
                if parts.count > 1 {
                    Text("· " + parts.dropFirst().joined(separator: " · "))
                        .softText(.caption).foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text.replacingOccurrences(of: " · ", with: ", "))
        }
    }
}
#endif
