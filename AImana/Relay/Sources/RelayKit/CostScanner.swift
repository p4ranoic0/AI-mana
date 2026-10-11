import AImanaCore
import Foundation

/// Walks the local Claude Code and Codex transcripts and turns them into `CostEvent`s.
/// Per-file results are cached by (mtime, size), so after the first run only changed files are re-read.
/// Message text is never decoded; only usage numbers, model ids and timestamps.
public struct CostScanner {
    enum Source { case claude, codex }

    private struct CachedFile: Codable {
        let mtime: Double
        let size: Int
        let events: [CostEvent]
    }

    private struct Cache: Codable {
        var version = 1
        var files: [String: CachedFile] = [:]
    }

    /// Files untouched for longer than this cannot contribute to the 30-day report.
    static let lookback: TimeInterval = 35 * 86400

    /// All events from both sources. Claude and Codex are scanned in one pass so the cache is written once.
    public static func scan(paths: RelayPaths, now: Date = Date()) -> (claude: [CostEvent], codex: [CostEvent], stats: String) {
        let started = Date()
        let cacheURL = paths.caches.appendingPathComponent("cost-cache.json")
        var cache = loadCache(cacheURL)
        var seen: Set<String> = []
        var claude: [CostEvent] = []
        var codex: [CostEvent] = []
        var parsed = 0, reused = 0
        let cutoff = now.addingTimeInterval(-lookback)

        for (source, bucket) in [(Source.claude, 0), (Source.codex, 1)] {
            for root in (source == .claude ? paths.claudeProjectRoots : paths.codexSessionRoots) {
                for file in jsonlFiles(under: root, modifiedAfter: cutoff) {
                    seen.insert(file.path)
                    let events: [CostEvent]
                    if let hit = cache.files[file.path], hit.mtime == file.mtime, hit.size == file.size {
                        events = hit.events
                        reused += 1
                    } else {
                        events = parse(file.url, source: source).filter { $0.timestamp >= cutoff }
                        cache.files[file.path] = CachedFile(mtime: file.mtime, size: file.size, events: events)
                        parsed += 1
                    }
                    if bucket == 0 { claude += events } else { codex += events }
                }
            }
        }
        // Forget files that disappeared or aged out.
        cache.files = cache.files.filter { seen.contains($0.key) }
        saveCache(cache, to: cacheURL)
        let seconds = String(format: "%.1f", Date().timeIntervalSince(started))
        return (claude, codex, "scanned \(parsed) changed + \(reused) cached files in \(seconds)s")
    }

    private struct FileInfo { let url: URL; let path: String; let mtime: Double; let size: Int }

    private static func jsonlFiles(under root: URL, modifiedAfter cutoff: Date) -> [FileInfo] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                          options: [.skipsHiddenFiles]) else { return [] }
        var result: [FileInfo] = []
        for case let url as URL in walker where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                  let modified = values.contentModificationDate, modified >= cutoff else { continue }
            result.append(FileInfo(url: url, path: url.path, mtime: modified.timeIntervalSince1970,
                                   size: values.fileSize ?? 0))
        }
        return result
    }

    private static func parse(_ url: URL, source: Source) -> [CostEvent] {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return [] }
        var events: [CostEvent] = []
        var codexParser = CodexLogParser()
        var lineStart = data.startIndex
        let newline = UInt8(ascii: "\n")
        while lineStart < data.endIndex {
            let lineEnd = data[lineStart...].firstIndex(of: newline) ?? data.endIndex
            let line = data[lineStart..<lineEnd]
            lineStart = lineEnd < data.endIndex ? data.index(after: lineEnd) : data.endIndex
            guard !line.isEmpty else { continue }
            switch source {
            case .claude: if let event = ClaudeLogParser.event(from: Data(line)) { events.append(event) }
            case .codex: if let event = codexParser.consume(Data(line)) { events.append(event) }
            }
        }
        return events
    }

    private static func loadCache(_ cacheURL: URL) -> Cache {
        guard let data = try? Data(contentsOf: cacheURL) else { return Cache() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let cache = try? decoder.decode(Cache.self, from: data), cache.version == 1 else { return Cache() }
        return cache
    }

    private static func saveCache(_ cache: Cache, to cacheURL: URL) {
        RelayPaths.ensure(cacheURL.deletingLastPathComponent())
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        if let data = try? encoder.encode(cache) { try? data.write(to: cacheURL, options: .atomic) }
    }
}
