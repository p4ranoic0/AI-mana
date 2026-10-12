import AImanaCore
import Foundation

/// Composition root: the only place that knows which providers exist and where their data comes from.
@MainActor
final class AppEnvironment {
    /// One per process: the app's scene and the intents Siri and the widgets run in the app share it, so a refresh
    /// started by either shows up in the other.
    static let shared = AppEnvironment()

    let service: UsageService
    private(set) lazy var dashboard = DashboardViewModel(service: service)

    /// Whether a relay file is reachable without the user picking one: a debug `-relay-file` path or `-demo` data.
    nonisolated static var hasRelayOverride: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-demo") || args.contains("-relay-file")
    }

    init() {
        let args = ProcessInfo.processInfo.arguments
        let providers: [any UsageProvider]
        if args.contains("-demo") {
            // `-demo-providers openrouter,codex` limits the sample to those providers (screenshots of one card).
            if let i = args.firstIndex(of: "-demo-providers"), args.indices.contains(i + 1) {
                let ids = Set(args[i + 1].split(separator: ",").map(String.init))
                providers = DemoProviders.all.filter { ids.contains($0.id) }
            } else {
                providers = DemoProviders.all
            }
        } else {
            // `-relay-file <path>` reads a plain file (simulator / debugging); otherwise the bookmarked iCloud Drive file.
            let source: any RelayDataSource
            if let i = args.firstIndex(of: "-relay-file"), args.indices.contains(i + 1) {
                source = CoordinatedFileSource(url: URL(fileURLWithPath: args[i + 1]))
            } else {
                source = BookmarkRelaySource()
            }
            let codex: any UsageProvider = RelayProvider(id: "codex", displayName: "OpenAI Codex", source: source)
            // Use the Mac relay when device credentials are unavailable.
            let claude: any UsageProvider = RelayProvider(id: "claude", displayName: "Claude Code", source: source)
            // OpenRouter: the user's own API key, official API; hidden until a key is saved in Settings.
            let openRouter = OpenRouterProvider(store: AppGroup.keychain())
            // GitHub Copilot: the user's own token, GitHub's official billing API; hidden until a token is saved.
            let copilot = CopilotProvider(store: AppGroup.keychain())
            // DeepSeek, Moonshot (Kimi), xAI: prepaid balances with the user's own key, same opt-in as OpenRouter.
            let balances: [any UsageProvider] = BalanceDescriptor.all.map {
                BalanceProvider(descriptor: $0, store: AppGroup.keychain())
            }
            let macOnly = MacOptionalProviders.make(source: source)
            providers = [claude, codex] + macOnly + [openRouter, copilot] + balances
        }
        service = UsageService(providers: providers, store: AppGroup.snapshotStore(),
                               history: AppGroup.historyStore())
    }
}
