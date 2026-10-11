import Foundation
import Testing
@testable import AImanaCore

@Suite struct SeverityTransitionsTests {
    private func state(_ remaining: Double?, id: String = "claude", error: UsageProviderError? = nil) -> ProviderState {
        let usage = remaining.map { value in
            UsageInfo(providerID: id, providerName: id, windows: [
                UsageWindow(kind: .session, usedPercent: 100 - value, windowMinutes: 300, resetsAt: nil)
            ], plan: nil, lastUpdated: .now)
        }
        return ProviderState(providerID: id, displayName: id, usage: usage, error: error)
    }

    @Test func warnsOnlyOnEscalation() {
        #expect(SeverityTransitions.hasEscalation(previous: [state(30)], current: [state(19)]))
        #expect(SeverityTransitions.hasEscalation(previous: [state(15)], current: [state(9)]))
        #expect(SeverityTransitions.hasEscalation(previous: [state(30)], current: [state(0)]))
        #expect(!SeverityTransitions.hasEscalation(previous: [state(15)], current: [state(16)]))
        #expect(!SeverityTransitions.hasEscalation(previous: [state(8)], current: [state(11)]))
        #expect(!SeverityTransitions.hasEscalation(previous: [], current: [state(5)]))
    }

    @Test func ignoresOtherProvidersAndFailedRefreshes() {
        #expect(!SeverityTransitions.hasEscalation(previous: [state(50)], current: [state(5, id: "codex")]))
        #expect(!SeverityTransitions.hasEscalation(previous: [state(50)], current: [state(5, error: .network)]))
        #expect(!SeverityTransitions.hasEscalation(previous: [state(50)], current: [state(nil)]))
    }
}
