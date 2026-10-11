import Foundation

/// Display rules ported from CodexBar's `UsageFormatter` (see Docs/UsageEndpoints.md §3).
/// `now` is injected so every rule is unit-testable.
public enum UsageFormatter {
    /// "3h 15m", "2d 5h", "15m", "now".
    public static func resetCountdown(to date: Date, now: Date = Date(), locale: Locale? = nil) -> String {
        let seconds = date.timeIntervalSince(now)
        guard seconds >= 1 else { return CoreStrings.text("now", locale: locale) }
        let total = max(1, Int(ceil(seconds / 60)))
        let days = total / 1440
        let hours = (total / 60) % 24
        let minutes = total % 60
        let d = CoreStrings.text("unit.day", locale: locale)
        let h = CoreStrings.text("unit.hour", locale: locale)
        let m = CoreStrings.text("unit.minute", locale: locale)
        if days > 0 {
            if hours > 0 { return "\(days)\(d) \(hours)\(h)" }
            if minutes > 0 { return "\(days)\(d) \(minutes)\(m)" }
            return "\(days)\(d)"
        }
        if hours > 0 { return minutes > 0 ? "\(hours)\(h) \(minutes)\(m)" : "\(hours)\(h)" }
        return "\(total)\(m)"
    }

    /// "Resets in 3h 15m", "Expired", or nil when the provider gave no reset.
    public static func resetText(for date: Date?, now: Date = Date(), locale: Locale? = nil) -> String? {
        guard let date else { return nil }
        guard date.timeIntervalSince(now) > 0 else { return CoreStrings.text("Expired", locale: locale) }
        return CoreStrings.format("Resets in %@", locale: locale,
                                  resetCountdown(to: date, now: now, locale: locale))
    }

    /// "82%", "<1%" for (0,1), clamped to 0...100.
    public static func percentText(_ value: Double) -> String {
        let clamped = min(100, max(0, value))
        if clamped > 0, clamped < 1 { return "<1%" }
        return String(format: "%.0f%%", clamped)
    }

    /// Stable USD presentation for the Mac's API-equivalent cost estimate. From $1,000 up the cents are dropped, so
    /// large totals fit beside small ones without shrinking.
    public static func usdText(_ amount: Double, locale: Locale = .current) -> String {
        let value = amount.isFinite ? amount : 0
        let digits = abs(value) >= 1000 ? 0 : 2
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits
        formatter.roundingMode = .halfUp
        return formatter.string(from: NSNumber(value: value)) ?? "$0.00"
    }

    /// Token totals in millions ("2,839 M", "18.4 M"); exact counts are too long to scan. Millions rather than the
    /// locale's compact notation, which reads badly in some languages (Spanish gives "2.84k M") and "B" is ambiguous.
    public static func tokenCountText(_ count: Int, locale: Locale = .current) -> String {
        let value = Double(count)
        if value >= 1_000_000 {
            let millions = value / 1_000_000
            let digits = millions >= 100 ? 0 : 1
            return millions.formatted(.number.precision(.fractionLength(digits)).locale(locale)) + " M"
        }
        if value >= 1_000 {
            return (value / 1_000).formatted(.number.precision(.fractionLength(value >= 100_000 ? 0 : 1)).locale(locale)) + " k"
        }
        return count.formatted(.number.locale(locale))
    }

    /// Readable model name from a log identifier: "claude-opus-5-5" → "Opus 5.5", "claude-sonnet-5-20260101" →
    /// "Sonnet 5", "gpt-5.3-codex" → "GPT-5.3-Codex". Unknown shapes pass through unchanged.
    public static func modelName(_ id: String) -> String {
        var parts = id.split(separator: "-").map(String.init)
        // Drop a trailing date stamp (8 digits).
        if let last = parts.last, last.count == 8, last.allSatisfy(\.isNumber) { parts.removeLast() }
        if parts.first == "claude", parts.count >= 2 {
            let family = parts[1].prefix(1).uppercased() + parts[1].dropFirst()
            let version = parts.dropFirst(2).filter { $0.allSatisfy(\.isNumber) }.joined(separator: ".")
            return version.isEmpty ? family : "\(family) \(version)"
        }
        if parts.first == "gpt" {
            return (["GPT"] + parts.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }).joined(separator: "-")
        }
        return id
    }

    /// Calendar day on this device; the relay's cost day keys use the same yyyy-MM-dd shape.
    public static func localDayString(for date: Date = Date(), timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// One-line pace summary, or nil when there is nothing meaningful to say. `compact` drops ", before reset".
    public static func paceText(_ pace: UsagePace, now: Date = Date(), compact: Bool = false,
                                locale: Locale? = nil) -> String? {
        switch pace.status {
        case .tooEarly: return nil
        case .depleted: return CoreStrings.text("Depleted", locale: locale)
        case .comfortable:
            // Nothing spent yet: there is no pace worth reporting.
            guard (pace.projectedUsedAtReset ?? 0) >= 1 else { return nil }
            let ends = Int(min(100, max(0, pace.projectedUsedAtReset ?? 0)).rounded())
            return CoreStrings.format("On pace · ends ~%d%% used", locale: locale, ends)
        case .fast:
            guard let exhausts = pace.exhaustsAt else { return CoreStrings.text("Fast", locale: locale) }
            let runsOut = CoreStrings.format("Fast · runs out in %@", locale: locale,
                                             resetCountdown(to: exhausts, now: now, locale: locale))
            return compact ? runsOut : runsOut + CoreStrings.text(", before reset", locale: locale)
        }
    }
}
