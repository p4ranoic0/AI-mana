import AImanaCore
import Foundation

/// Reads the file the statusline wrapper writes. No credentials, no network.
public enum ClaudeStatuslineReader {
    public static func read(file: URL, now: Date) -> Result<UsageInfo, UsageProviderError> {
        guard let data = try? Data(contentsOf: file) else { return .failure(.relayUnavailable) }
        let mtime = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        do {
            return .success(try ClaudeStatuslineSource.usage(from: data, fallbackCapturedAt: mtime, now: now))
        } catch let error as UsageProviderError {
            return .failure(error)
        } catch {
            return .failure(.decoding)
        }
    }
}

/// Finds the newest Codex `rate_limits` event without reading whole logs: files are visited newest first by
/// modification date, each is read from the end in growing chunks, and the total bytes read are capped.
public enum CodexLogReader {
    public struct Limits: Sendable {
        public var maxFiles: Int
        public var maxBytesPerFile: Int
        public var maxTotalBytes: Int
        public var firstChunk: Int

        public init(maxFiles: Int = 12, maxBytesPerFile: Int = 2 << 20, maxTotalBytes: Int = 8 << 20,
                    firstChunk: Int = 64 << 10) {
            self.maxFiles = maxFiles
            self.maxBytesPerFile = maxBytesPerFile
            self.maxTotalBytes = maxTotalBytes
            self.firstChunk = firstChunk
        }
    }

    public static func read(roots: [URL], limits: Limits = Limits()) -> Result<UsageInfo, UsageProviderError> {
        var budget = limits.maxTotalBytes
        var best: UsageInfo?
        for file in newestFiles(under: roots).prefix(limits.maxFiles) {
            // Nothing in a file last written before the best event can be newer than it.
            if let best, file.mtime < best.lastUpdated { break }
            guard budget > 0 else { break }
            let (found, used) = latest(in: file.url, size: file.size, limits: limits, budget: budget)
            budget -= used
            if let found, best == nil || found.lastUpdated > best!.lastUpdated { best = found }
        }
        return best.map { .success($0) } ?? .failure(.relayUnavailable)
    }

    struct FileInfo { let url: URL; let mtime: Date; let size: Int }

    static func newestFiles(under roots: [URL]) -> [FileInfo] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        var result: [FileInfo] = []
        for root in roots {
            guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                              options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in walker where url.pathExtension == "jsonl" {
                guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                      let mtime = values.contentModificationDate else { continue }
                result.append(FileInfo(url: url, mtime: mtime, size: values.fileSize ?? 0))
            }
        }
        return result.sorted { $0.mtime > $1.mtime }
    }

    /// Reads growing tails (64 KB, 128 KB, …) until an event is found, the file start is reached, or a cap is hit.
    static func latest(in url: URL, size: Int, limits: Limits, budget: Int) -> (UsageInfo?, Int) {
        guard size > 0, let handle = try? FileHandle(forReadingFrom: url) else { return (nil, 0) }
        defer { try? handle.close() }
        var chunk = min(limits.firstChunk, size)
        var used = 0
        while true {
            let readLength = min(chunk, size, limits.maxBytesPerFile, budget - used)
            guard readLength > 0 else { return (nil, used) }
            let offset = size - readLength
            guard (try? handle.seek(toOffset: UInt64(offset))) != nil,
                  let data = try? handle.read(upToCount: readLength) else { return (nil, used) }
            used += data.count
            if let found = CodexLogSource.latestUsage(inJSONL: data, startsMidLine: offset > 0) { return (found, used) }
            if offset == 0 || readLength >= limits.maxBytesPerFile || used >= budget { return (nil, used) }
            chunk *= 2
        }
    }
}
