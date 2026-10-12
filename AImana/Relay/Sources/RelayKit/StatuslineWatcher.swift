import Foundation

/// Calls back when Claude Code rewrites the statusline capture file (on every message), so the Mac can publish
/// right away instead of waiting for the next timer tick.
///
/// The wrapper replaces the file atomically (temp file + `mv`), which would orphan a watch on the file itself, so the
/// watch is on its directory: a kernel event (`DispatchSource`, no polling, no CPU while idle). The directory also
/// holds other AImana files (history, locks, notification state), so an event only counts when the capture file's
/// modification date actually changed.
#if canImport(Darwin)
public final class StatuslineWatcher: @unchecked Sendable {
    private let file: URL
    private let queue = DispatchQueue(label: "aimana.statusline-watcher", qos: .utility)
    private let onChange: @Sendable (Date) -> Void
    private var source: DispatchSourceFileSystemObject?
    private var lastSeen: Date?

    public init(file: URL, onChange: @escaping @Sendable (Date) -> Void) {
        self.file = file
        self.onChange = onChange
    }

    deinit { source?.cancel() }

    /// Starts watching. Returns false when the directory cannot be opened (it is created first if missing).
    @discardableResult
    public func start() -> Bool {
        queue.sync {
            guard source == nil else { return true }
            let dir = file.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let fd = open(dir.path, O_EVTONLY)
            guard fd >= 0 else { return false }
            lastSeen = modificationDate()
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename],
                                                                   queue: queue)
            source.setEventHandler { [weak self] in self?.check() }
            source.setCancelHandler { close(fd) }
            source.resume()
            self.source = source
            return true
        }
    }

    public func stop() {
        queue.sync {
            source?.cancel()
            source = nil
        }
    }

    private func check() {
        guard let date = modificationDate(), date != lastSeen else { return }
        lastSeen = date
        onChange(date)
    }

    private func modificationDate() -> Date? {
        // Not `URL.resourceValues`: it caches per URL instance and would keep returning the first date.
        (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date
    }
}
#endif

#if os(Windows)
/// Windows has no DispatchSourceFileSystemObject. Poll the capture's metadata while the watcher is active.
public final class StatuslineWatcher: @unchecked Sendable {
    private let file: URL
    private let queue = DispatchQueue(label: "aimana.statusline-watcher", qos: .utility)
    private let onChange: @Sendable (Date) -> Void
    private var source: DispatchSourceTimer?
    private var lastSeen: Date?

    public init(file: URL, onChange: @escaping @Sendable (Date) -> Void) {
        self.file = file
        self.onChange = onChange
    }

    deinit { source?.cancel() }

    @discardableResult
    public func start() -> Bool {
        queue.sync {
            guard source == nil else { return true }
            do {
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            } catch { return false }
            lastSeen = modificationDate()
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 1, repeating: 1)
            timer.setEventHandler { [weak self] in self?.check() }
            timer.resume()
            source = timer
            return true
        }
    }

    public func stop() {
        queue.sync { source?.cancel(); source = nil }
    }

    private func check() {
        guard let date = modificationDate(), date != lastSeen else { return }
        lastSeen = date
        onChange(date)
    }

    private func modificationDate() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date
    }
}
#endif

/// When a publish triggered by fresh statusline data should run: shortly after the change (so a burst of messages
/// collapses into one publish), but never sooner than `minInterval` after the previous publish started.
public enum PublishDebounce {
    public static let settle: TimeInterval = 3
    public static let minInterval: TimeInterval = 30

    public static func delay(lastPublishStart: Date?, now: Date, minInterval: TimeInterval = minInterval,
                             settle: TimeInterval = settle) -> TimeInterval {
        guard let last = lastPublishStart else { return settle }
        return max(settle, minInterval - now.timeIntervalSince(last))
    }
}
