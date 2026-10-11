import Foundation

/// Reads Codex quota from its own session logs (`~/.codex/sessions/**/*.jsonl`). Codex writes the account's
/// rate limits into every `token_count` event:
/// `{"timestamp": "...Z", "type": "event_msg", "payload": {"type": "token_count", "info": {...},
///   "rate_limits": {"limit_id": "codex", "primary": {"used_percent": 93.0, "window_minutes": 300, "resets_at": 1787703892},
///   "secondary": {...}, "credits": {...}, "plan_type": "plus"}}}`.
///
/// Only those fields are decoded — never message text. `lastUpdated` is the event's own timestamp, so an old
/// log never looks fresh. Separate from `CodexProvider`'s endpoint mapper on purpose: the shapes differ.
public enum CodexLogSource {
    public static let providerID = "codex"
    public static let providerName = "OpenAI Codex"

    private struct Window: Decodable {
        let used_percent: Double
        let window_minutes: Int?
        let resets_at: Double?
    }

    private struct Credits: Decodable {
        let has_credits: Bool?
        let unlimited: Bool?
        let balance: Double?

        enum CodingKeys: String, CodingKey { case has_credits, unlimited, balance }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            has_credits = try? c.decode(Bool.self, forKey: .has_credits)
            unlimited = try? c.decode(Bool.self, forKey: .unlimited)
            if let n = try? c.decode(Double.self, forKey: .balance) { balance = n }
            else { balance = (try? c.decode(String.self, forKey: .balance)).flatMap { Double($0) } }
        }
    }

    private struct RateLimits: Decodable {
        let limit_id: String?
        let primary: Lossy<Window>?
        let secondary: Lossy<Window>?
        let credits: Lossy<Credits>?
        let plan_type: String?
    }

    private struct Line: Decodable {
        struct Payload: Decodable {
            let type: String?
            let rate_limits: Lossy<RateLimits>?
        }
        let timestamp: String?
        let type: String?
        let payload: Payload?
    }

    /// The account-wide lane set. Other ids (e.g. "premium") carry no windows or belong to a single model.
    static let mainLimitID = "codex"

    /// Usage from one JSONL line, or nil when the line is not a usable rate-limit event.
    public static func usage(fromLine line: Data) -> UsageInfo? {
        guard line.range(of: Data("\"rate_limits\"".utf8)) != nil,
              let decoded = try? JSONDecoder().decode(Line.self, from: line),
              decoded.type == "event_msg", decoded.payload?.type == "token_count",
              let limits = decoded.payload?.rate_limits?.value,
              limits.limit_id == nil || limits.limit_id == mainLimitID,
              let stamp = decoded.timestamp, let date = ISO8601DateFormatter.parseLoose(stamp) else { return nil }
        return map(limits, timestamp: date)
    }

    /// The newest usable event in a chunk of a JSONL file. When `startsMidLine` is true (the chunk is the tail of a
    /// larger file) the first, partial line is ignored.
    public static func latestUsage(inJSONL chunk: Data, startsMidLine: Bool) -> UsageInfo? {
        var lines = chunk.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false)
        if startsMidLine, !lines.isEmpty { lines.removeFirst() }
        // Codex appends chronologically, so the last usable line is the newest event.
        for line in lines.reversed() where !line.isEmpty {
            if let usage = usage(fromLine: Data(line)) { return usage }
        }
        return nil
    }

    /// Of several candidates (one per file), the one with the newest event timestamp.
    public static func newest(_ candidates: [UsageInfo]) -> UsageInfo? {
        candidates.max { $0.lastUpdated < $1.lastUpdated }
    }

    private static func map(_ limits: RateLimits, timestamp: Date) -> UsageInfo? {
        typealias Slot = (minutes: Int?, used: Double, reset: Date?)
        func slot(_ raw: Window?) -> Slot? {
            guard let raw, raw.used_percent.isFinite else { return nil }
            let reset = raw.resets_at.flatMap { $0.isFinite && $0 > 0 ? Date(timeIntervalSince1970: $0) : nil }
            return (raw.window_minutes, raw.used_percent, reset)
        }
        // Classify by duration, never by slot position: 300 min = session, 10080 min = weekly.
        var session: UsageWindow?
        var weekly: UsageWindow?
        var unknown: [Slot] = []
        for s in [slot(limits.primary?.value), slot(limits.secondary?.value)].compactMap({ $0 }) {
            switch s.minutes {
            case 300: session = UsageWindow(kind: .session, usedPercent: s.used, windowMinutes: 300, resetsAt: s.reset)
            case 10080: weekly = UsageWindow(kind: .weekly, usedPercent: s.used, windowMinutes: 10080, resetsAt: s.reset)
            default: unknown.append(s)
            }
        }
        // Unrecognised durations: the shorter one is the session lane, the longer the weekly one.
        for s in unknown.sorted(by: { ($0.minutes ?? .max) < ($1.minutes ?? .max) }) {
            if session == nil, (s.minutes ?? 0) < 1440 {
                session = UsageWindow(kind: .session, usedPercent: s.used, windowMinutes: s.minutes, resetsAt: s.reset)
            } else if weekly == nil {
                weekly = UsageWindow(kind: .weekly, usedPercent: s.used, windowMinutes: s.minutes, resetsAt: s.reset)
            }
        }
        let windows = [session, weekly].compactMap { $0 }
        guard !windows.isEmpty else { return nil }
        var details: [UsageDetail] = []
        if let credits = limits.credits?.value, credits.has_credits == true, credits.unlimited != true,
           let balance = credits.balance, balance.isFinite, balance > 0 {
            details.append(UsageDetail(kind: .creditBalance, remaining: balance, currency: "USD"))
        }
        return UsageInfo(providerID: providerID, providerName: providerName, windows: windows,
                         plan: limits.plan_type, lastUpdated: timestamp, details: details)
    }
}
