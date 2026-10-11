#if canImport(SwiftUI)
import SwiftUI

public extension UsageSeverity {
    var tint: Color {
        switch self {
        case .normal: .green
        case .warning: .orange
        case .critical: .red
        }
    }

    var statusText: String {
        switch self {
        case .normal: CoreStrings.text("Quota available")
        case .warning: CoreStrings.text("Running low")
        case .critical: CoreStrings.text("Almost exhausted")
        }
    }
}

/// A quota ring whose fill follows the chosen headline while its tint follows remaining quota.
public struct UsageRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animatedValue = 0.0
    public let window: UsageWindow
    public let mode: DisplayMode
    public let size: CGFloat

    public init(window: UsageWindow, mode: DisplayMode, size: CGFloat = 104) {
        self.window = window
        self.mode = mode
        self.size = size
    }

    private var severity: UsageSeverity { UsageSeverity(remainingPercent: window.remainingPercent) }
    private var value: Double { mode.percent(for: window) }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: max(6, size * 0.085))
            Circle()
                .trim(from: 0, to: animatedValue / 100)
                .stroke(severity.tint, style: StrokeStyle(lineWidth: max(6, size * 0.085), lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(UsageFormatter.percentText(value))
                    .font(.system(size: size * 0.25, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .identity : .numericText())
                    .animation(reduceMotion ? nil : .smooth, value: value)
                    .lineLimit(1)   // "100%" must never wrap into "100" / "%"
                    .minimumScaleFactor(0.5)
                if size >= 90 {
                    Text(mode.caption)
                        .font(.system(size: size * 0.105, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .padding(size * 0.15)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(UsageFormatter.percentText(value)) \(mode.caption), \(severity.statusText.lowercased())")
        .onAppear { updateFill() }
        .onChange(of: value) { _, _ in updateFill() }
        .onChange(of: reduceMotion) { _, _ in updateFill() }
    }

    private func updateFill() {
        if reduceMotion { animatedValue = value }
        else { withAnimation(.smooth(duration: 0.7)) { animatedValue = value } }
    }
}

/// Session on the outside and weekly quota inside, with one legible headline value.
public struct UsageConcentricRings: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animatedSession = 0.0
    @State private var animatedWeekly = 0.0
    public let session: UsageWindow
    public let weekly: UsageWindow
    public let mode: DisplayMode
    public let size: CGFloat
    public let sessionPace: UsagePace?
    public let showsCenterValue: Bool

    public init(session: UsageWindow, weekly: UsageWindow, mode: DisplayMode, size: CGFloat = 176,
                sessionPace: UsagePace? = nil, showsCenterValue: Bool = true) {
        self.session = session
        self.weekly = weekly
        self.mode = mode
        self.size = size
        self.sessionPace = sessionPace
        self.showsCenterValue = showsCenterValue
    }

    /// Angle of the "even spender" tick on the outer ring, matching the ring's fill scale.
    private var tickDegrees: Double? {
        guard let sessionPace, sessionPace.status != .depleted else { return nil }
        let expected = sessionPace.expectedUsedPercent
        return (mode == .used ? expected : 100 - expected) / 100 * 360
    }

    private var sessionSeverity: UsageSeverity { UsageSeverity(remainingPercent: session.remainingPercent) }
    private var weeklySeverity: UsageSeverity { UsageSeverity(remainingPercent: weekly.remainingPercent) }
    private var weeklyTint: Color { weeklySeverity.tint }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: max(4, size * 0.075))
            Circle()
                .trim(from: 0, to: animatedSession / 100)
                .stroke(sessionSeverity.tint,
                        style: StrokeStyle(lineWidth: max(4, size * 0.075), lineCap: .round))
                .rotationEffect(.degrees(-90))
            if let degrees = tickDegrees {
                Capsule()
                    .fill(.primary.opacity(0.75))
                    .frame(width: 2.5, height: max(4, size * 0.075) + 7)
                    .offset(y: -(size / 2 - max(4, size * 0.075) / 2))
                    .rotationEffect(.degrees(degrees))
                    .accessibilityHidden(true)
            }
            Circle()
                .stroke(.quaternary, lineWidth: max(3, size * 0.06))
                .frame(width: size * 0.72, height: size * 0.72)
            Circle()
                .trim(from: 0, to: animatedWeekly / 100)
                .stroke(weeklyTint,
                        style: StrokeStyle(lineWidth: max(3, size * 0.06), lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: size * 0.72, height: size * 0.72)
            if showsCenterValue {
                VStack(spacing: 1) {
                Text(UsageFormatter.percentText(mode.percent(for: session)))
                    .font(.system(size: size * 0.27, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .identity : .numericText())
                    .animation(reduceMotion ? nil : .smooth, value: mode.percent(for: session))
                    .lineLimit(1)   // "100%" must never wrap into "100" / "%"
                    .minimumScaleFactor(0.5)
                if size >= 100 {
                    Text("\(CoreStrings.text("Session")) \(mode.caption)")
                        .font(.system(size: size * 0.075, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                }
                .padding(size * 0.23)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(CoreStrings.format("Session %@ %@, %@. Weekly %@ %@, %@",
                                               UsageFormatter.percentText(mode.percent(for: session)),
                                               mode.caption, sessionSeverity.statusText,
                                               UsageFormatter.percentText(mode.percent(for: weekly)),
                                               mode.caption, weeklySeverity.statusText))
        .onAppear { updateFills() }
        .onChange(of: mode.percent(for: session)) { _, _ in updateFills() }
        .onChange(of: mode.percent(for: weekly)) { _, _ in updateFills() }
        .onChange(of: reduceMotion) { _, _ in updateFills() }
    }

    private func updateFills() {
        let sessionValue = mode.percent(for: session)
        let weeklyValue = mode.percent(for: weekly)
        if reduceMotion {
            animatedSession = sessionValue
            animatedWeekly = weeklyValue
        } else {
            withAnimation(.smooth(duration: 0.7)) {
                animatedSession = sessionValue
                animatedWeekly = weeklyValue
            }
        }
    }
}
#endif
