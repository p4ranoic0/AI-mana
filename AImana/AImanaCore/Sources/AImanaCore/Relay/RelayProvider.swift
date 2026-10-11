import Foundation

public protocol RelayDataSource: Sendable {
    func readData() async throws -> Data
}

/// Reads a file with `NSFileCoordinator`, first asking iCloud to download it if it is only a placeholder.
#if !os(Linux)
public struct CoordinatedFileSource: RelayDataSource {
    private let url: URL
    private let downloadTimeout: TimeInterval

    public init(url: URL, downloadTimeout: TimeInterval = 8) {
        self.url = url
        self.downloadTimeout = downloadTimeout
    }

    public func readData() async throws -> Data {
        let url = self.url
        let timeout = downloadTimeout
        return try await Task.detached {
            try Self.ensureDownloaded(url, timeout: timeout)
            var coordinationError: NSError?
            var result: Result<Data, Error> = .failure(UsageProviderError.relayUnavailable)
            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readURL in
                result = Result { try Data(contentsOf: readURL) }
            }
            if coordinationError != nil { throw UsageProviderError.relayUnavailable }
            do { return try result.get() } catch { throw UsageProviderError.relayUnavailable }
        }.value
    }

    private static func ensureDownloaded(_ url: URL, timeout: TimeInterval) throws {
        let keys: Set<URLResourceKey> = [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
        guard let values = try? url.resourceValues(forKeys: keys), values.isUbiquitousItem == true else { return }
        if values.ubiquitousItemDownloadingStatus == .current { return }
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let status = try? url.resourceValues(forKeys: keys).ubiquitousItemDownloadingStatus
            if status == .current { return }
            Thread.sleep(forTimeInterval: 0.25)
        }
    }
}
#endif

/// Thrown by an opt-in relay provider (`hiddenUntilPublished`) when the Mac does not publish it: the provider is
/// then left off the dashboard instead of showing an empty "not found" card. `relayReadable` tells whether the
/// file itself was read (the Mac stopped publishing this provider) or not (a passing iCloud problem).
public struct RelayEntryAbsent: Error, Sendable, Equatable {
    public let relayReadable: Bool

    public init(relayReadable: Bool) {
        self.relayReadable = relayReadable
    }
}

/// Serves one provider's usage out of the Mac-published relay file. Providers stay interchangeable:
/// the UI cannot tell a relay-backed provider from a direct one.
public struct RelayProvider: UsageProvider {
    public let id: String
    public let displayName: String
    /// Opt-in Mac providers that most users never turn on: shown only while the relay has them.
    public let hiddenUntilPublished: Bool
    private let source: any RelayDataSource

    public init(id: String, displayName: String, source: any RelayDataSource, hiddenUntilPublished: Bool = false) {
        self.id = id
        self.displayName = displayName
        self.source = source
        self.hiddenUntilPublished = hiddenUntilPublished
    }

    public var hidesWithoutData: Bool { hiddenUntilPublished }

    public func fetchUsage() async throws -> UsageInfo {
        let envelope: RelayEnvelope
        do {
            envelope = try RelayEnvelope.decode(try await source.readData())
        } catch {
            if hiddenUntilPublished { throw RelayEntryAbsent(relayReadable: false) }
            throw error
        }
        guard let entry = envelope.entries.first(where: { $0.providerID == id }) else {
            if hiddenUntilPublished { throw RelayEntryAbsent(relayReadable: true) }
            throw UsageProviderError.relayUnavailable
        }
        if let usage = entry.usage {
            return usage.withExtras(cost: envelope.costs.first { $0.providerID == id },
                                    history: envelope.history.filter { $0.providerID == id })
                .withSource(entry.source)
        }
        throw (entry.error ?? .relayUnavailable).providerError
    }
}
