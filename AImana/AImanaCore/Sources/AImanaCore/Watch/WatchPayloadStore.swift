import Foundation

/// The watch's copy of the last payload from the iPhone, shared by the watch app and its complications through the
/// App Group (Application Support when the group is unavailable, e.g. unsigned simulator builds).
public final class WatchPayloadStore: @unchecked Sendable {
    public static let fileName = "watch-payload.json"
    private let fileURL: URL
    private let lock = NSLock()

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func shared() -> WatchPayloadStore {
        #if !canImport(Darwin)
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        #else
        let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        #endif
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return WatchPayloadStore(fileURL: dir.appendingPathComponent(fileName))
    }

    public func load() -> WatchPayload? {
        lock.lock(); defer { lock.unlock() }
        return (try? Data(contentsOf: fileURL)).flatMap(WatchPayload.decode)
    }

    /// Keeps whichever payload was sent last: application context and complication transfers can arrive out of
    /// order. Returns false when `payload` is older than the saved one and was ignored.
    @discardableResult
    public func save(_ payload: WatchPayload) throws -> Bool {
        lock.lock(); defer { lock.unlock() }
        if let data = try? Data(contentsOf: fileURL), let saved = WatchPayload.decode(data),
           saved.sentAt > payload.sentAt { return false }
        try payload.encoded().write(to: fileURL, options: .atomic)
        return true
    }

    public func clear() {
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.removeItem(at: fileURL)
    }
}
