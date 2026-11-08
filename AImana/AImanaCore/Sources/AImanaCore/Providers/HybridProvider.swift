import Foundation

/// Reads usage straight from the provider with this device's own sign-in when there is one, and uses the Mac relay
/// as a fallback and as the source of costs and history (which only exist in the Mac's local logs). The relay is
/// optional: with a direct sign-in the app keeps working while the Mac is off.
public struct HybridProvider: UsageProvider {
    public var id: String { direct.id }
    public var displayName: String { direct.displayName }
    private let direct: any UsageProvider
    private let relay: any UsageProvider
    private let isDirectEnabled: @Sendable () -> Bool

    public init(direct: any UsageProvider, relay: any UsageProvider, isDirectEnabled: @escaping @Sendable () -> Bool) {
        self.direct = direct
        self.relay = relay
        self.isDirectEnabled = isDirectEnabled
    }

    public func fetchUsage() async throws -> UsageInfo {
        let fromRelay = try? await relay.fetchUsage()
        guard isDirectEnabled() else {
            if let fromRelay { return fromRelay }
            throw UsageProviderError.relayUnavailable
        }
        let live: UsageInfo
        do {
            live = try await direct.fetchUsage()
        } catch {
            let directError = (error as? UsageProviderError) ?? .network
            // Show the relay's data, but never hide that direct access failed.
            if let fromRelay { throw DirectFallback(usage: fromRelay, directError: directError) }
            throw error
        }
        // Turned off while the request was in flight: the direct reading must not come back.
        guard isDirectEnabled() else {
            if let fromRelay { return fromRelay }
            throw UsageProviderError.relayUnavailable
        }
        return UsageInfo(providerID: live.providerID, providerName: live.providerName, windows: live.windows,
                         plan: live.plan ?? fromRelay?.plan, lastUpdated: live.lastUpdated, details: live.details,
                         cost: fromRelay?.cost, history: fromRelay?.history ?? [])
    }
}

/// Thrown by `HybridProvider` when direct access failed but the relay has data: `UsageService` shows that data
/// together with the direct error, as a fallback.
public struct DirectFallback: Error, Sendable {
    public let usage: UsageInfo
    public let directError: UsageProviderError

    public init(usage: UsageInfo, directError: UsageProviderError) {
        self.usage = usage
        self.directError = directError
    }
}
