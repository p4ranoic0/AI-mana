import Foundation

/// The one-paragraph answer Siri, Shortcuts and the Control Center control give: "Claude Code: Session 22% used,
/// resets in 3h; Weekly 67% used, fast pace, runs out in 1d 17h." Pure, so every rule is unit-testable; `now` and
/// `locale` are injected.
public enum UsageAnswer {
    /// Readings older than this are refreshed before answering (Siri, Shortcuts, the widgets' refresh button).
    public static let maximumAge: TimeInterval = 5 * 60
    /// Older readings say how old they are, so a stale answer is never taken for a current one.
    static let staleAge: TimeInterval = 15 * 60

    /// Display names for providers the snapshot does not contain yet.
    static let knownNames = ["claude": "Claude Code", "codex": "OpenAI Codex"]

    /// Answer for `providerIDs` in that order, one line per provider. Providers the snapshot lacks say so.
    public static func text(items: [UsageInfo], providerIDs: [String], mode: DisplayMode,
                            now: Date = Date(), locale: Locale? = nil) -> String {
        let found = providerIDs.compactMap { id in items.first { $0.providerID == id && !$0.windows.isEmpty } }
        if found.isEmpty {
            return CoreStrings.text("No usage yet. Open AI·mana to load it.", locale: locale)
        }
        return providerIDs.map { id in
            if let info = found.first(where: { $0.providerID == id }) {
                return line(for: info, mode: mode, now: now, locale: locale)
            }
            return CoreStrings.format("%@: no data yet.", locale: locale, knownNames[id] ?? id)
        }.joined(separator: "\n")
    }

    /// "Claude Code: Session 22% used, resets in 3h; Weekly 67% used, fast pace, runs out in 1d 17h."
    public static func line(for info: UsageInfo, mode: DisplayMode, now: Date = Date(), locale: Locale? = nil) -> String {
        var lanes = [info.window(.session), info.window(.weekly)].compactMap { $0 }
        if lanes.isEmpty, let primary = info.primary { lanes = [primary] }
        let body = lanes.map { lane($0, info: info, mode: mode, now: now, locale: locale) }.joined(separator: "; ")
        var result = CoreStrings.format("%1$@: %2$@.", locale: locale, info.providerName, body)
        if now.timeIntervalSince(info.lastUpdated) > staleAge {
            let age = UsageFormatter.resetCountdown(to: now, now: info.lastUpdated, locale: locale)
            result += " " + CoreStrings.format("Last updated %@ ago.", locale: locale, age)
        }
        return result
    }

    static func laneName(_ kind: UsageWindow.Kind, locale: Locale?) -> String {
        switch kind {
        case .session: CoreStrings.text("Session", locale: locale)
        case .weekly: CoreStrings.text("Weekly", locale: locale)
        case .model(let name), .modelSession(let name): name
        default: kind.title
        }
    }

    /// "Session 22% used, resets in 3h" / "Weekly 33% left, about 8% per day, resets in 4d 1h".
    static func lane(_ window: UsageWindow, info: UsageInfo, mode: DisplayMode, now: Date, locale: Locale?) -> String {
        let name = laneName(window.kind, locale: locale)
        if window.isOutdated(now: now) {
            return CoreStrings.format("%@ has reset since the last reading", locale: locale, name)
        }
        var parts = [percentPhrase(name: name, window: window, mode: mode, locale: locale)]
        let pace = UsagePace(window: window, now: now)
        if pace?.status == .fast, let exhausts = pace?.exhaustsAt {
            parts.append(CoreStrings.format("fast pace, runs out in %@", locale: locale,
                                            UsageFormatter.resetCountdown(to: exhausts, now: now, locale: locale)))
        } else {
            if let budget = DailyBudget(window: window, history: info.history, providerID: info.providerID, now: now),
               budget.status == .spread {
                parts.append(CoreStrings.format("about %@ per day", locale: locale,
                                                UsageFormatter.percentText(budget.perDayPercent)))
            }
            if let reset = window.resetsAt {
                parts.append(CoreStrings.format("resets in %@", locale: locale,
                                                UsageFormatter.resetCountdown(to: reset, now: now, locale: locale)))
            }
        }
        return parts.joined(separator: ", ")
    }

    /// "Claude Code 22% used" / "Claude Code 78% left": one lane in a few words, for the Control Center control.
    public static func compact(_ info: UsageInfo, window: UsageWindow, mode: DisplayMode, locale: Locale? = nil) -> String {
        percentPhrase(name: info.providerName, window: window, mode: mode, locale: locale)
    }

    static func percentPhrase(name: String, window: UsageWindow, mode: DisplayMode, locale: Locale?) -> String {
        let percent = UsageFormatter.percentText(mode.percent(for: window))
        return mode == .used
            ? CoreStrings.format("%1$@ %2$@ used", locale: locale, name, percent)
            : CoreStrings.format("%1$@ %2$@ left", locale: locale, name, percent)
    }

    /// Whether any of `providerIDs` is missing from the snapshot or older than `maxAge`.
    public static func needsRefresh(items: [UsageInfo], providerIDs: [String],
                                    maxAge: TimeInterval = maximumAge, now: Date = Date()) -> Bool {
        providerIDs.contains { id in
            guard let info = items.first(where: { $0.providerID == id }) else { return true }
            return now.timeIntervalSince(info.lastUpdated) >= maxAge
        }
    }

    /// The most urgent current session for a compact control: the highest used % (or lowest left %) across
    /// providers. Falls back to a provider's headline lane when none reports a session. Outdated lanes are skipped.
    public static func urgentSession(items: [UsageInfo], mode: DisplayMode,
                                     now: Date = Date()) -> (info: UsageInfo, window: UsageWindow)? {
        let candidates = items.compactMap { info -> (UsageInfo, UsageWindow)? in
            guard let window = info.window(.session) ?? info.primary, !window.isOutdated(now: now) else { return nil }
            return (info, window)
        }
        // Urgency is what is left, whichever mode is displayed.
        return candidates.min { $0.1.remainingPercent < $1.1.remainingPercent }.map { (info: $0.0, window: $0.1) }
    }
}

public extension RefreshSchedule {
    /// A user asked (refresh button, Siri): never wait for the chosen interval, only skip readings younger than
    /// `maxAge`. The short gap keeps repeated taps from firing a request each.
    static let onDemandGap: TimeInterval = 20

    static func isDueOnDemand(snapshot: [UsageInfo], providerIDs: [String], maxAge: TimeInterval,
                              lastAttempt: Date?, now: Date) -> Bool {
        guard !providerIDs.isEmpty else { return false }
        if let lastAttempt, lastAttempt <= now, now.timeIntervalSince(lastAttempt) < onDemandGap { return false }
        return UsageAnswer.needsRefresh(items: snapshot, providerIDs: providerIDs, maxAge: maxAge, now: now)
    }
}
