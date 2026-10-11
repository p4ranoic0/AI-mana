#if canImport(SwiftUI)
import SwiftUI

/// Quota bar shared by the dashboard and widgets. It fills with the value being headlined (used or remaining),
/// while its colour always reflects how much is left, so "75% used" still reads as a warning.
public struct UsageBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animatedFraction = 0.0
    public let window: UsageWindow
    public let mode: DisplayMode
    public let pace: UsagePace?

    public init(window: UsageWindow, mode: DisplayMode, pace: UsagePace? = nil) {
        self.window = window
        self.mode = mode
        self.pace = pace
    }

    /// Where an even spender would be right now, on the same scale as the fill (flips in Remaining mode).
    private var markerFraction: Double? {
        guard let pace, pace.status != .depleted else { return nil }
        let expected = pace.expectedUsedPercent
        return (mode == .used ? expected : 100 - expected) / 100
    }

    private var severity: UsageSeverity { UsageSeverity(remainingPercent: window.remainingPercent) }
    private var targetFraction: Double { max(0, min(1, mode.percent(for: window) / 100)) }

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(severity.tint)
                    .frame(width: animatedFraction * proxy.size.width)
            }
            // The pace marker overhangs the bar as an overlay, so it never makes the bar itself taller.
            .overlay(alignment: .leading) {
                if let fraction = markerFraction {
                    Capsule()
                        .fill(.primary.opacity(0.75))
                        .frame(width: 2.5, height: 16)
                        .offset(x: max(0, min(1, fraction)) * proxy.size.width - 1.25)
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(height: 8)
        .accessibilityElement()
        .accessibilityLabel(mode.title)
        .accessibilityValue("\(UsageFormatter.percentText(mode.percent(for: window))) \(mode.caption), \(severity.statusText.lowercased())")
        .onAppear { updateFill() }
        .onChange(of: targetFraction) { _, _ in updateFill() }
        .onChange(of: reduceMotion) { _, _ in updateFill() }
    }

    private func updateFill() {
        if reduceMotion { animatedFraction = targetFraction }
        else { withAnimation(.smooth(duration: 0.65)) { animatedFraction = targetFraction } }
    }
}
#endif

public extension UsageWindow.Kind {
    var title: String {
        switch self {
        case .session: CoreStrings.text("Session (5h)")
        case .weekly: CoreStrings.text("Weekly")
        case .model(let name): CoreStrings.format("Weekly · %@", name)
        case .modelSession(let name): CoreStrings.format("Session · %@", name)
        case .spendLimit: CoreStrings.text("Spending limit")
        case .freeRequests: CoreStrings.text("Free-model requests (day)")
        case .monthly: CoreStrings.text("Monthly")
        }
    }
}
