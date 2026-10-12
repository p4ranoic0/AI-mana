import Foundation
import Testing
@testable import AImanaCore

@Suite struct DemoProvidersTests {
    @Test func sharedScreenshotsUseSameReadingsAndCosts() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let mac = DemoProviders.macEnvelope(now: now)
        let watch = DemoProviders.watchPayload(now: now)

        #expect(mac.entries.map(\.providerID) == ["claude", "codex"])
        #expect(watch.providers.map(\.id) == ["claude", "codex"])
        for (entry, provider) in zip(mac.entries, watch.providers) {
            #expect(entry.usage?.window(.session)?.usedPercent == provider.session?.usedPercent)
            #expect(entry.usage?.window(.weekly)?.usedPercent == provider.weekly?.usedPercent)
        }
        #expect(watch.providers[0].session?.usedPercent == 18)
        #expect(watch.providers[0].weekly?.usedPercent == 42)
        #expect(watch.providers[1].session?.usedPercent == 33)
        #expect(watch.providers[1].weekly?.usedPercent == 61)
        #expect(mac.costs.allSatisfy { $0.days.count == 30 && $0.days.allSatisfy { $0.models.count == 2 } })
    }
}
