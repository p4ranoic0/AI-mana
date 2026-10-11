import Foundation
#if os(Linux)
import CoreFoundation
#endif

/// Parses the file AImana's statusline wrapper writes from Claude Code's official statusline JSON:
/// `{"capturedAt": <epoch s | ISO 8601>, "rate_limits": {"five_hour": {"used_percentage": 23.5, "resets_at": 1738425600},
/// "seven_day": {...}}}` (shape from https://code.claude.com/docs/en/statusline; Pro/Max only, each window optional).
///
/// Staleness rules:
/// - `lastUpdated` is when Claude Code rendered the statusline (`capturedAt`), never when the file was read, so
///   republishing the same capture every few minutes does not make it look fresh.
/// - A window whose `resets_at` has passed is kept with its last reading; `UsageWindow.isOutdated` flags it.
///   It is never turned into 0 %.
/// - A missing `rate_limits` (not Pro/Max, or no response yet in the session) is `.relayUnavailable`, not 0 %.
public enum ClaudeStatuslineSource {
    public static let fileName = "claude-statusline.json"
    public static let providerID = "claude"
    public static let providerName = "Claude Code"

    /// - Parameters:
    ///   - fallbackCapturedAt: used only when the file has no readable `capturedAt` (e.g. the file's mtime).
    ///   - now: a capture stamped in the future (clock skew) is clamped to `now`.
    public static func usage(from data: Data, fallbackCapturedAt: Date? = nil, now: Date) throws -> UsageInfo {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw UsageProviderError.decoding
        }
        guard let captured = date(root["capturedAt"]) ?? fallbackCapturedAt else { throw UsageProviderError.decoding }
        guard let limits = root["rate_limits"] as? [String: Any] else { throw UsageProviderError.relayUnavailable }

        let windows = [window(limits["five_hour"], kind: .session, minutes: 300),
                       window(limits["seven_day"], kind: .weekly, minutes: 10080)].compactMap { $0 }
        guard !windows.isEmpty else { throw UsageProviderError.relayUnavailable }
        return UsageInfo(providerID: providerID, providerName: providerName, windows: windows, plan: nil,
                         lastUpdated: min(captured, now))
    }

    private static func window(_ raw: Any?, kind: UsageWindow.Kind, minutes: Int) -> UsageWindow? {
        guard let dict = raw as? [String: Any], let used = number(dict["used_percentage"]), used.isFinite else { return nil }
        return UsageWindow(kind: kind, usedPercent: used, windowMinutes: minutes, resetsAt: date(dict["resets_at"]))
    }

    public static func number(_ value: Any?) -> Double? {
        if let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { return n.doubleValue }
        if let s = value as? String { return Double(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    /// Epoch seconds (or milliseconds, if implausibly large) or an ISO 8601 string.
    static func date(_ value: Any?) -> Date? {
        if let s = value as? String, let d = ISO8601DateFormatter.parseLoose(s) { return d }
        guard let n = number(value), n.isFinite, n > 0 else { return nil }
        return Date(timeIntervalSince1970: n > 100_000_000_000 ? n / 1000 : n)
    }
}
