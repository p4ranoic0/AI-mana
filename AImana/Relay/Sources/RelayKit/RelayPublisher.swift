import AImanaCore
import Foundation

public struct RelayOptions: Sendable, Equatable {
    public var output: URL
    /// Endpoint identifiers requested in addition to the local sources.
    public var endpointProviderIDs: Set<String>
    /// Extra providers supplied by an external provider factory.
    public var optionalProviderIDs: [String]
    public var refreshOptionalProviders: Bool
    public var includeCosts: Bool
    /// Allow refreshing the public pricing cache while calculating local costs.
    public var allowPricingDownload: Bool

    public init(output: URL = RelayPaths.defaultOutput, endpointProviderIDs: Set<String> = [],
                optionalProviderIDs: [String] = [], refreshOptionalProviders: Bool = true,
                includeCosts: Bool = true, allowPricingDownload: Bool = true) {
        self.output = output
        self.endpointProviderIDs = endpointProviderIDs
        self.optionalProviderIDs = optionalProviderIDs
        self.refreshOptionalProviders = refreshOptionalProviders
        self.includeCosts = includeCosts
        self.allowPricingDownload = allowPricingDownload
    }
}

public struct PublishReport: Sendable {
    public let envelope: RelayEnvelope
    public let output: URL
    public let finishedAt: Date
    /// What each opted-in endpoint answered this pass, even when the local source won and hid its failure.
    /// Providers whose endpoint was not asked are absent.
    public var endpoints: [String: EndpointOutcome] = [:]

    /// Whether the Mac's own access works, judged only from the endpoint calls (the local sources never sign in):
    /// rejected → expired, answered → active, not asked → signed out (clears an old alert), other failures say nothing.
    public func macLogins(providerIDs: [String]) -> [String: PhoneLoginStatus] {
        var result: [String: PhoneLoginStatus] = [:]
        for id in providerIDs {
            switch endpoints[id] {
            case nil: result[id] = .signedOut
            case .success: result[id] = .active
            case .failure(.unauthenticated): result[id] = .expired
            case .failure: break
            }
        }
        return result
    }
}

public enum EndpointOutcome: Sendable, Equatable {
    case success
    case failure(RelayErrorCode)
}

public enum RelayPublishError: Error, Sendable, Equatable {
    /// Another relay (the old CLI job or a second app) held the lock for too long.
    case busy
    case writeFailed(String)
}

/// One publishing pass, shared by the `usage-relay` CLI and the Mac app: read local sources (and the opt-in
/// endpoints), choose per provider with `RelaySourcePolicy`, record history, attach local costs, and write the
/// v1 envelope atomically. A lock file in the state directory keeps two relays from interleaving, so the relay
/// stays the single writer of its history.
public struct RelayPublisher: Sendable {
    public typealias EndpointFactory = @Sendable (_ providerID: String, _ options: RelayOptions) -> (any UsageProvider)?

    private let paths: RelayPaths
    private let log: @Sendable (String) -> Void
    private let endpoints: EndpointFactory
    private let clock: @Sendable () -> Date

    public init(paths: RelayPaths = .standard,
                log: @escaping @Sendable (String) -> Void = { _ in },
                endpoints: EndpointFactory? = nil,
                clock: @escaping @Sendable () -> Date = { Date() }) {
        self.paths = paths
        self.log = log
        self.endpoints = endpoints ?? { _, _ in nil }
        self.clock = clock
    }

    public func publish(_ options: RelayOptions) async throws -> PublishReport {
        RelayPaths.ensure(paths.stateDirectory)
        do {
            return try await FileLock(url: paths.lockFile, timeout: 120).withLock { try await publishLocked(options) }
        } catch let error as ProcessLockError {
            log("lock: \(error)")
            throw RelayPublishError.busy
        }
    }

    private func publishLocked(_ options: RelayOptions) async throws -> PublishReport {
        let now = clock()
        var outcomes: [String: EndpointOutcome] = [:]
        let claude = await entry(id: "claude", enabled: options.endpointProviderIDs.contains("claude"), options: options,
                                 local: ClaudeStatuslineReader.read(file: paths.claudeStatuslineFile, now: now),
                                 localSource: .statusline, outcomes: &outcomes)
        let codex = await entry(id: "codex", enabled: options.endpointProviderIDs.contains("codex"), options: options,
                                local: CodexLogReader.read(roots: paths.codexSessionRoots), localSource: .logs,
                                outcomes: &outcomes)
        // Opt-in providers with no local fallback: present in the file only while turned on, so the iPhone shows
        // them only then. Extra publishes (statusline changes) copy their last entries instead of asking again.
        var entries = [claude, codex]
        let previous = options.refreshOptionalProviders ? nil
            : (try? RelayEnvelope.decode(Data(contentsOf: options.output)))?.entries
        for id in options.optionalProviderIDs {
            if let kept = previous?.first(where: { $0.providerID == id }) {
                entries.append(kept)
            } else {
                entries.append(await optionalEntry(id: id, options: options, outcomes: &outcomes))
            }
        }
        for e in entries {
            log("\(e.providerID): \(e.source?.rawValue ?? "-") \(e.error.map { "error \($0.rawValue)" } ?? "ok")")
        }

        let history = HistoryRecorder.record(HistoryStore.load(from: paths.historyFile),
                                             with: entries.compactMap(\.usage), now: now)
        HistoryStore.save(history, to: paths.historyFile)
        let costs = options.includeCosts ? await buildCosts(now: now, allowDownload: options.allowPricingDownload) : []
        let envelope = RelayEnvelope(generatedAt: now, entries: entries, costs: costs,
                                     history: HistoryRecorder.downsampled(history, now: now))
        do {
            try FileManager.default.createDirectory(at: options.output.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try AtomicRelayFile.write(envelope.encoded(), to: options.output)
        } catch {
            log("write failed: \(error)")
            throw RelayPublishError.writeFailed(error.localizedDescription)
        }
        log("wrote \(options.output.path)")
        return PublishReport(envelope: envelope, output: options.output, finishedAt: clock(), endpoints: outcomes)
    }

    private func entry(id: String, enabled: Bool, options: RelayOptions,
                       local: Result<UsageInfo, UsageProviderError>, localSource: RelaySource,
                       outcomes: inout [String: EndpointOutcome]) async -> RelayEntry {
        var endpoint: Result<UsageInfo, UsageProviderError>?
        if enabled, let provider = endpoints(id, options) {
            do {
                endpoint = .success(try await provider.fetchUsage())
            } catch let error as UsageProviderError {
                log("\(id) endpoint: \(error)")
                endpoint = .failure(error)
            } catch {
                log("\(id) endpoint: \(error)")
                endpoint = .failure(.network)
            }
        }
        switch endpoint {
        case .success: outcomes[id] = .success
        case .failure(let error): outcomes[id] = .failure(RelayErrorCode(error))
        case nil: break
        }
        return RelaySourcePolicy.entry(providerID: id, endpoint: endpoint, local: local, localSource: localSource)
    }

    private func optionalEntry(id: String, options: RelayOptions,
                               outcomes: inout [String: EndpointOutcome]) async -> RelayEntry {
        guard let provider = endpoints(id, options) else {
            return RelayEntry(providerID: id, usage: nil, error: .relayUnavailable, source: .endpoint)
        }
        do {
            let usage = try await provider.fetchUsage()
            outcomes[id] = .success
            return RelayEntry(providerID: id, usage: usage, error: nil, source: .endpoint)
        } catch {
            let code = (error as? UsageProviderError).map(RelayErrorCode.init) ?? .network
            log("\(id): \(code.rawValue)")
            outcomes[id] = .failure(code)
            return RelayEntry(providerID: id, usage: nil, error: code, source: .endpoint)
        }
    }

    /// Cost reports for both providers from the local transcripts. Failures here never block publishing usage.
    public func buildCosts(now: Date, allowDownload: Bool = true) async -> [CostReport] {
        let pricing = await PricingStore.load(caches: paths.caches, now: now, allowDownload: allowDownload)
        if pricing.prices.isEmpty { log("no pricing available; costs will show tokens only") }
        let scan = CostScanner.scan(paths: paths, now: now)
        log(scan.stats)
        var claude = CostAggregator(priceProvider: "anthropic", pricing: pricing)
        scan.claude.forEach { claude.add($0) }
        var codex = CostAggregator(priceProvider: "openai", pricing: pricing)
        scan.codex.forEach { codex.add($0) }
        return [claude.report(providerID: "claude", now: now, days: 30),
                codex.report(providerID: "codex", now: now, days: 30)]
    }
}
