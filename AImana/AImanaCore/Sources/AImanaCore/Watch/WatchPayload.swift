import Foundation

/// What the iPhone sends to the Apple Watch: only the quota lanes, their resets and how old each reading is.
/// No history, costs, credits or credentials, so it stays far below WatchConnectivity's limits (well under 1 KB
/// for two providers) and the watch never needs the network.
///
/// Short coding keys on purpose: the same bytes go through `updateApplicationContext` after every refresh.
public struct WatchPayload: Codable, Sendable, Equatable {
    public static let currentVersion = 1
    /// Key of the encoded payload inside the WatchConnectivity dictionaries.
    public static let messageKey = "aimana.watch.v1"
    /// Key the watch sends (by message) to ask the iPhone for its last saved reading.
    public static let requestKey = "aimana.watch.request"
    /// More lanes than this per provider are dropped (session and weekly always come first).
    static let maxLanesPerProvider = 4

    public struct Lane: Codable, Sendable, Equatable {
        public let kind: UsageWindow.Kind
        public let used: Double
        public let minutes: Int?
        public let resetsAt: Date?

        enum CodingKeys: String, CodingKey { case kind = "k", used = "u", minutes = "m", resetsAt = "r" }

        public init(kind: UsageWindow.Kind, used: Double, minutes: Int?, resetsAt: Date?) {
            self.kind = kind
            self.used = used
            self.minutes = minutes
            self.resetsAt = resetsAt
        }

        public init(_ window: UsageWindow) {
            // One decimal is all any screen shows, and it keeps the JSON short.
            let used = window.usedPercent.isFinite ? (window.usedPercent * 10).rounded() / 10 : 0
            self.init(kind: window.kind, used: used, minutes: window.windowMinutes,
                      resetsAt: window.resetsAt.map { Date(timeIntervalSince1970: $0.timeIntervalSince1970.rounded()) })
        }

        public var window: UsageWindow {
            UsageWindow(kind: kind, usedPercent: used, windowMinutes: minutes, resetsAt: resetsAt)
        }
    }

    public struct Provider: Codable, Sendable, Equatable, Identifiable {
        public enum Issue: String, Codable, Sendable {
            /// The iPhone needs the user to sign in again; the numbers (if any) are the last known ones.
            case signIn = "auth"
            /// The last refresh failed; the numbers are the last known ones.
            case stale
        }

        public let id: String
        public let name: String
        /// When the reading was taken (the provider's `lastUpdated`), not when it was sent.
        public let updatedAt: Date?
        public let lanes: [Lane]
        public let issue: Issue?

        enum CodingKeys: String, CodingKey { case id, name = "n", updatedAt = "t", lanes = "l", issue = "e" }

        public init(id: String, name: String, updatedAt: Date?, lanes: [Lane], issue: Issue?) {
            self.id = id
            self.name = name
            self.updatedAt = updatedAt
            self.lanes = lanes
            self.issue = issue
        }

        public func window(_ kind: UsageWindow.Kind) -> UsageWindow? {
            lanes.first { $0.kind == kind }?.window
        }

        public var session: UsageWindow? { window(.session) }
        public var weekly: UsageWindow? { window(.weekly) }
        /// Headline lane, same rule as `UsageInfo.primary`.
        public var primary: UsageWindow? { session ?? weekly ?? lanes.first?.window }
    }

    public let version: Int
    public let sentAt: Date
    /// The phone's Used / Remaining choice, so the watch headlines the same number.
    public let mode: DisplayMode
    public let providers: [Provider]

    enum CodingKeys: String, CodingKey { case version = "v", sentAt = "s", mode = "d", providers = "p" }

    public init(sentAt: Date, mode: DisplayMode, providers: [Provider]) {
        self.version = Self.currentVersion
        self.sentAt = sentAt
        self.mode = mode
        self.providers = providers
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        sentAt = try c.decode(Date.self, forKey: .sentAt)
        mode = (try? c.decode(DisplayMode.self, forKey: .mode)) ?? .used
        providers = try c.decode([Provider].self, forKey: .providers)
    }

    /// Builds the payload from a refresh. Providers with neither data nor an issue worth showing are left out.
    public init(states: [ProviderState], mode: DisplayMode, now: Date = Date()) {
        let providers = states.compactMap { state -> Provider? in
            let issue: Provider.Issue? = switch state.error {
            case nil: nil
            case .unauthenticated?: .signIn
            default: .stale
            }
            guard state.usage != nil || issue == .signIn else { return nil }
            // Balance-only providers (DeepSeek, Moonshot, xAI) have no quota lanes to show on the watch.
            if let usage = state.usage, usage.windows.isEmpty { return nil }
            return Provider(id: state.providerID, name: state.displayName, updatedAt: state.usage?.lastUpdated,
                            lanes: Self.lanes(state.usage?.windows ?? []), issue: issue)
        }
        self.init(sentAt: now, mode: mode, providers: providers)
    }

    /// Builds the payload from the saved snapshot (no errors known), e.g. to answer the watch's request.
    public init(snapshot: [UsageInfo], mode: DisplayMode, now: Date = Date()) {
        self.init(sentAt: now, mode: mode, providers: snapshot.filter { !$0.windows.isEmpty }.map {
            Provider(id: $0.providerID, name: $0.providerName, updatedAt: $0.lastUpdated,
                     lanes: Self.lanes($0.windows), issue: nil)
        })
    }

    private static func lanes(_ windows: [UsageWindow]) -> [Lane] {
        let rank: (UsageWindow.Kind) -> Int = { kind in
            switch kind {
            case .session: 0
            case .weekly: 1
            case .modelSession: 2
            case .model: 3
            default: 4
            }
        }
        let ordered = windows.enumerated().sorted { a, b in
            (rank(a.element.kind), a.offset) < (rank(b.element.kind), b.offset)
        }
        return ordered.prefix(maxLanesPerProvider).map { Lane($0.element) }
    }

    // MARK: - Wire format

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) -> WatchPayload? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let payload = try? decoder.decode(WatchPayload.self, from: data),
              payload.version <= currentVersion else { return nil }
        return payload
    }

    /// The dictionary handed to WatchConnectivity (property-list types only).
    public func message() throws -> [String: Any] {
        [Self.messageKey: try encoded()]
    }

    public static func from(message: [String: Any]) -> WatchPayload? {
        (message[messageKey] as? Data).flatMap(decode)
    }

    // MARK: - Reading it on the watch

    /// The provider with the fullest session (or primary) lane, which complications headline.
    public var busiest: Provider? { busiest(at: Date()) }

    /// Same, judged at `date`: a lane whose window already reset is not current, so a stale 100 % never outranks a
    /// live reading. Falls back to all lanes when every one has reset (the views then show the reading as stale).
    public func busiest(at date: Date) -> Provider? {
        let withLane = providers.filter { $0.primary != nil }
        let current = withLane.filter { !($0.primary?.isOutdated(now: date) ?? true) }
        return (current.isEmpty ? withLane : current).max { a, b in
            (a.primary?.displayUsedPercent ?? 0) < (b.primary?.displayUsedPercent ?? 0)
        }
    }

    /// Oldest reading among providers that have one.
    public var oldestUpdate: Date? {
        providers.compactMap(\.updatedAt).min()
    }

    // MARK: - Complication budget

    /// Whether this payload differs enough from `previous` to spend one of the day's limited complication
    /// transfers (`transferCurrentComplicationUserInfo`). Everything else rides on the application context, which
    /// the watch picks up the next time it wakes.
    ///
    /// - A provider appearing, disappearing or changing sign-in state, a lane resetting, or a severity change always
    ///   counts (while any budget is left).
    /// - A shift of `step` points or more in a provider's headline lane counts while more than `reserve`
    ///   transfers remain, so the last few are kept for the changes that matter most.
    public func isMeaningfulChange(from previous: WatchPayload?, remainingTransfers: Int,
                                   step: Double = 5, reserve: Int = 10) -> Bool {
        guard remainingTransfers > 0 else { return false }
        guard let previous else { return true }
        let old = Dictionary(previous.providers.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        if Set(old.keys) != Set(providers.map(\.id)) || previous.mode != mode { return true }
        var bigShift = false
        for provider in providers {
            guard let before = old[provider.id] else { return true }
            if (before.issue == .signIn) != (provider.issue == .signIn) { return true }
            for lane in provider.lanes {
                guard let was = before.lanes.first(where: { $0.kind == lane.kind }) else { return true }
                let now = lane.window, then = was.window
                if UsageSeverity(remainingPercent: now.remainingPercent)
                    != UsageSeverity(remainingPercent: then.remainingPercent) { return true }
                // A new window started: the reset time moved forward.
                if let a = lane.resetsAt, let b = was.resetsAt, a.timeIntervalSince(b) > 60 { return true }
            }
            if let now = provider.primary, let then = before.primary,
               abs(now.displayUsedPercent - then.displayUsedPercent) >= step { bigShift = true }
        }
        return bigShift && remainingTransfers > reserve
    }
}
