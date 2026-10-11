import Foundation

/// Localized titles and bodies for planned notifications. Titles name the provider and lane; bodies say what to do.
struct NotificationText {
    let locale: Locale?
    let now: Date

    private func thread(_ providerID: String) -> String { "provider.\(providerID)" }

    private func instance(_ state: WindowAlertState) -> Int {
        Int(state.resetsAt?.timeIntervalSince1970 ?? 0)
    }

    private func title(_ state: WindowAlertState) -> String {
        "\(state.providerName) · \(CoreStrings.text(laneKey(state.lane), locale: locale))"
    }

    private func laneKey(_ lane: AlertLane) -> String { lane == .session ? "Session (5h)" : "Weekly" }

    /// "Resets in 3h 15m." or empty when the provider gave no reset time.
    private func resetSentence(_ window: UsageWindow) -> String {
        UsageFormatter.resetText(for: window.resetsAt, now: now, locale: locale).map { " \($0)." } ?? ""
    }

    func threshold(_ threshold: Int, used: Double, window: UsageWindow, state: WindowAlertState,
                   key: String) -> PlannedNotification {
        let body = CoreStrings.format("Now at %1$@ used, past your %2$@ alert.", locale: locale,
                                      UsageFormatter.percentText(used),
                                      UsageFormatter.percentText(Double(threshold))) + resetSentence(window)
        return PlannedNotification(id: "threshold.\(key).\(instance(state)).\(threshold)", kind: .threshold(threshold),
                                   providerID: state.providerID, lane: state.lane, title: title(state), body: body,
                                   threadID: thread(state.providerID), trigger: .now)
    }

    func fastPace(exhausts: Date, window: UsageWindow, state: WindowAlertState, key: String) -> PlannedNotification {
        let runsOut = UsageFormatter.resetCountdown(to: exhausts, now: now, locale: locale)
        let body: String
        if let resetsAt = window.resetsAt {
            body = CoreStrings.format("At this pace it runs out in %1$@, before the reset in %2$@.", locale: locale,
                                      runsOut, UsageFormatter.resetCountdown(to: resetsAt, now: now, locale: locale))
        } else {
            body = CoreStrings.format("At this pace it runs out in %@, before it resets.", locale: locale, runsOut)
        }
        return PlannedNotification(id: "pace.\(key).\(instance(state))", kind: .fastPace,
                                   providerID: state.providerID, lane: state.lane, title: title(state), body: body,
                                   threadID: thread(state.providerID), trigger: .now)
    }

    /// Scheduled for the reset time when it is known; sent right away when a reset is only noticed afterwards.
    func recovered(_ state: WindowAlertState, key: String, immediateID: Bool) -> PlannedNotification {
        let trigger: PlannedNotification.Trigger = immediateID ? .now : .at(state.resetsAt ?? now)
        let id = immediateID ? "recovery-now.\(key).\(instance(state))" : "recovered.\(key)"
        return PlannedNotification(id: id, kind: .recovered, providerID: state.providerID, lane: state.lane,
                                   title: title(state),
                                   body: CoreStrings.text("It has reset. Quota is available again.", locale: locale),
                                   threadID: thread(state.providerID), trigger: trigger)
    }

    func loginExpired(providerID: String, displayName: String, origin: LoginAlertOrigin = .phone) -> PlannedNotification {
        if origin == .thisMac {
            // Shown on the Mac itself: the CLI there has to sign in again.
            return PlannedNotification(
                id: "login.\(providerID)", kind: .loginExpired, providerID: providerID, lane: nil,
                title: CoreStrings.format("AImana for Mac lost access to %@", locale: locale, displayName),
                body: CoreStrings.format("Sign in to %@ again on this Mac so AImana keeps getting your detailed usage.",
                                         locale: locale, displayName),
                threadID: thread(providerID), trigger: .now)
        }
        if origin == .mac {
            // The Mac reads the CLI's own sign-in, so the fix happens in the tool there.
            return PlannedNotification(
                id: "login.\(providerID)", kind: .loginExpired, providerID: providerID, lane: nil,
                title: CoreStrings.format("AImana for Mac lost access to %@", locale: locale, displayName),
                body: CoreStrings.format("Sign in to %@ again on your Mac so this iPhone keeps getting your usage.",
                                         locale: locale, displayName),
                threadID: thread(providerID), trigger: .now)
        }
        // The phone signs in to the account, not the tool: ChatGPT for Codex.
        let account = switch providerID {
        case "claude": "Claude"
        case "codex": "ChatGPT"
        default: displayName
        }
        return PlannedNotification(
            id: "login.\(providerID)", kind: .loginExpired, providerID: providerID, lane: nil,
            title: CoreStrings.format("%@ sign-in expired", locale: locale, account),
            body: CoreStrings.text("Open AImana and sign in again in Settings so this iPhone keeps updating your usage.",
                                   locale: locale),
            threadID: thread(providerID), trigger: .now)
    }

    /// One line per provider. Lanes that reset before the notification fires say so instead of showing old numbers.
    func dailySummary(usages: [UsageInfo], mode: DisplayMode, nextFire: Date, hour: Int, minute: Int,
                      id: String, thread: String) -> PlannedNotification {
        var lines: [String] = usages.map { usage in
            let parts = AlertLane.allCases.compactMap { lane -> String? in
                guard let window = usage.window(lane.kind) else { return nil }
                let value: String
                if let resetsAt = window.resetsAt, resetsAt <= nextFire {
                    value = CoreStrings.text("renewed", locale: locale)
                } else {
                    let percent = UsageFormatter.percentText(mode.percent(for: window))
                    value = CoreStrings.format(mode == .used ? "%@ used" : "%@ left", locale: locale, percent)
                }
                return "\(CoreStrings.text(laneKey(lane), locale: locale)) \(value)"
            }
            return parts.isEmpty ? usage.providerName : "\(usage.providerName): \(parts.joined(separator: " · "))"
        }
        if let newest = usages.map(\.lastUpdated).max() {
            let formatter = DateFormatter()
            formatter.locale = locale ?? Locale(identifier: Locale.preferredLanguages.first ?? "en")
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            lines.append(CoreStrings.format("Data from %@", locale: locale, formatter.string(from: newest)))
        } else {
            lines.append(CoreStrings.text("No usage data yet.", locale: locale))
        }
        return PlannedNotification(id: id, kind: .dailySummary, providerID: nil, lane: nil,
                                   title: CoreStrings.text("Daily usage summary", locale: locale),
                                   body: lines.joined(separator: "\n"), threadID: thread,
                                   trigger: .daily(hour: hour, minute: minute))
    }
}
