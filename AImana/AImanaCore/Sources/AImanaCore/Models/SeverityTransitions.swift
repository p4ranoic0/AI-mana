import Foundation

/// True when a fresh quota reading enters a more urgent low-quota severity.
public enum SeverityTransitions {
    public static func hasEscalation(previous: [ProviderState], current: [ProviderState]) -> Bool {
        let old = Dictionary(uniqueKeysWithValues: previous.compactMap { state -> (String, UsageInfo)? in
            guard state.error == nil, let usage = state.usage else { return nil }
            return (state.providerID, usage)
        })
        for state in current where state.error == nil {
            guard let before = old[state.providerID], let after = state.usage else { continue }
            for window in after.windows {
                guard let prior = before.window(window.kind) else { continue }
                let oldLevel = level(UsageSeverity(remainingPercent: prior.remainingPercent))
                let newLevel = level(UsageSeverity(remainingPercent: window.remainingPercent))
                if newLevel > oldLevel && newLevel > 0 { return true }
            }
        }
        return false
    }

    private static func level(_ severity: UsageSeverity) -> Int {
        switch severity {
        case .normal: 0
        case .warning: 1
        case .critical: 2
        }
    }
}

public extension SeverityTransitions {
    /// User thresholds (used %) passed while going from `previous` to `current` used %, minus those already
    /// announced for this window instance. Always measured on used %, independent of the display mode.
    static func crossedThresholds(_ thresholds: [Int], from previous: Double, to current: Double,
                                  alreadyFired: Set<Int> = []) -> [Int] {
        thresholds.filter { threshold in
            let value = Double(threshold)
            return previous < value && current >= value && !alreadyFired.contains(threshold)
        }.sorted()
    }
}
