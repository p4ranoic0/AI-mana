import AImanaCore
import AppIntents
import SwiftUI

// Compiled into both the app and the widget extension (project.yml): Siri and Shortcuts run these in the app, the
// widgets' refresh button and the Control Center control need them in the extension too. Each target supplies its
// own `IntentRefreshRunner`: the app refreshes through its `UsageService`; the extension uses `WidgetRefresher`.

enum UsageProviderChoice: String, AppEnum {
    case all, claude, codex

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Provider")
    static let caseDisplayRepresentations: [UsageProviderChoice: DisplayRepresentation] = [
        .all: DisplayRepresentation(title: "All providers", synonyms: ["All", "Everything"]),
        .claude: DisplayRepresentation(title: "Claude Code", synonyms: ["Claude"]),
        .codex: DisplayRepresentation(title: "OpenAI Codex", synonyms: ["Codex"]),
    ]

    var providerIDs: [String] {
        switch self {
        case .all: ["claude", "codex"]
        case .claude: ["claude"]
        case .codex: ["codex"]
        }
    }
}

/// "How much is left in AI·mana?": the saved reading, refreshed first when it is over five minutes old.
struct GetUsageIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Usage"
    static let description = IntentDescription("Says how much of your Claude Code and OpenAI Codex quota is used or left, with pace and reset times.")

    @Parameter(title: "Provider", default: .all)
    var provider: UsageProviderChoice

    static var parameterSummary: some ParameterSummary {
        Summary("Get usage for \(\.$provider)")
    }

    init() {}

    init(provider: UsageProviderChoice) {
        self.provider = provider
    }

    /// Siri waits a few seconds at most; past this the answer uses what is saved and the fetch finishes on its own.
    static let refreshDeadline: TimeInterval = 8

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog & ShowsSnippetView {
        let ids = provider.providerIDs
        await IntentRefreshRunner.refresh(providerIDs: ids, maxAge: UsageAnswer.maximumAge,
                                          deadline: Self.refreshDeadline)
        let items = AppGroup.snapshotStore().load()
        let mode = DisplayPreferences.mode()
        let now = Date()
        let answer = UsageAnswer.text(items: items, providerIDs: ids, mode: mode, now: now)
        let shown = ids.compactMap { id in items.first { $0.providerID == id && $0.primary != nil } }
        return .result(value: answer, dialog: IntentDialog("\(answer)"),
                       view: UsageSnippetView(items: shown, mode: mode, now: now))
    }
}

/// Fetches now (the widgets' refresh button, Siri, Shortcuts) and reloads the widgets.
///
/// A `LiveActivityIntent` so that a tap on the widget button runs it in the app's process, which can also read the
/// Mac relay; a plain intent would run in the widget extension without access to the relay file.
struct RefreshUsageIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Refresh Usage"
    static let description = IntentDescription("Fetches the latest Claude Code and OpenAI Codex usage and updates the widgets.")

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        await IntentRefreshRunner.refresh(providerIDs: UsageProviderChoice.all.providerIDs, maxAge: 0, deadline: 20)
        return .result()
    }
}

/// Opens the dashboard, which refreshes on its own when it comes to the foreground.
struct OpenAImanaIntent: AppIntent {
    static let title: LocalizedStringResource = "Open AI·mana"
    static let description = IntentDescription("Opens AI·mana's dashboard.")
    static let openAppWhenRun = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        .result()
    }
}

/// Returns when `work` finishes or after `seconds`, whichever comes first, without cancelling `work`.
enum IntentDeadline {
    static func run(_ seconds: TimeInterval, _ work: @escaping @Sendable () async -> Void) async {
        let once = Once()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            Task {
                await work()
                if once.claim() { continuation.resume() }
            }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
                if once.claim() { continuation.resume() }
            }
        }
    }

    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var claimed = false
        func claim() -> Bool { lock.withLock { defer { claimed = true }; return !claimed } }
    }
}

/// Shown under Siri's answer: each provider's session and weekly lanes as bars.
struct UsageSnippetView: View {
    let items: [UsageInfo]
    let mode: DisplayMode
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(items) { info in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: SoftTheme.providerSymbol(info.providerID))
                            .font(.caption).foregroundStyle(SoftTheme.providerTint(info.providerID))
                        Text(info.providerName).font(.subheadline.weight(.semibold))
                    }
                    ForEach([info.window(.session), info.window(.weekly)].compactMap { $0 }, id: \.kind) { window in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(window.kind.title).font(.caption).foregroundStyle(.secondary)
                                Spacer(minLength: 4)
                                Text(UsageFormatter.percentText(mode.percent(for: window)))
                                    .font(.system(.caption, design: .rounded, weight: .bold)).monospacedDigit()
                            }
                            UsageBar(window: window, mode: mode, pace: UsagePace(window: window, now: now))
                                .frame(height: 6)
                        }
                    }
                }
            }
        }
        .padding()
    }
}
