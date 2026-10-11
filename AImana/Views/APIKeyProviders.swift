import AImanaCore
import SwiftUI

/// Providers the user connects with their own API key, read through each provider's official API. Each one shows up
/// on the dashboard only while its key is saved; keys go to the shared Keychain group so the widgets can refresh too.
struct APIKeyProvider: Identifiable {
    let id: String
    let name: String
    let credentialKey: String
    /// Localized placeholder, help footer and "key rejected" message.
    let placeholder: String
    let help: String
    let rejected: String
    /// One request with the pasted key before it is saved.
    let validate: @Sendable (String) async throws -> Void
    /// A provider-specific explanation for a failed check, when the generic one would mislead.
    var describe: (@Sendable (UsageProviderError) -> String?)? = nil

    static let openRouter = APIKeyProvider(
        id: OpenRouterProvider.providerID, name: OpenRouterProvider.name,
        credentialKey: CredentialKey.openRouterAPIKey,
        placeholder: AppStrings.text("Paste your OpenRouter API key"),
        help: AppStrings.text("Create a key at openrouter.ai/keys. AI·mana reads only its usage and limits through OpenRouter's official API. The key stays in the iOS Keychain on this iPhone."),
        rejected: AppStrings.text("OpenRouter did not accept this key."),
        validate: { _ = try await OpenRouterProvider.validate(key: $0) })

    static let deepSeek = balance(.deepSeek,
        help: AppStrings.text("Create a key at platform.deepseek.com/api_keys. AI·mana reads only your balance through DeepSeek's official API. The key stays in the iOS Keychain on this iPhone."))

    static let moonshot = balance(.moonshot,
        help: AppStrings.text("Create a key at platform.kimi.ai, or at platform.kimi.com for the China platform; AI·mana finds the right one by itself. It reads only your balance through the official Kimi API. The key stays in the iOS Keychain on this iPhone."))

    /// xAI's balance is only readable with a management key, so this one asks for that and says why.
    static let xAI = balance(.xAI,
        placeholder: AppStrings.text("Paste your xAI management key"),
        help: AppStrings.text("xAI shows the prepaid balance only to a management key, not to a regular API key. Create one in the xAI Console under Settings → Management Keys, with access to billing. AI·mana reads only the balance. The key stays in the iOS Keychain on this iPhone."),
        rejected: AppStrings.text("xAI did not accept this key. Use a management key with access to billing."))

    /// GitHub's billing API with a personal access token; the plan (for the included allowance) is picked on its screen.
    static let copilot = APIKeyProvider(
        id: CopilotProvider.providerID, name: CopilotProvider.name,
        credentialKey: CredentialKey.gitHubCopilotToken,
        placeholder: AppStrings.text("Paste your GitHub token"),
        help: AppStrings.text("On github.com, open Settings → Developer settings → Personal access tokens → Fine-grained tokens → Generate new token. Under Account permissions, set Plan to Read-only; nothing else is needed. AI·mana reads only your Copilot usage report through GitHub's official billing API. The token stays in the iOS Keychain on this iPhone."),
        rejected: AppStrings.text("GitHub did not accept this token. It needs the Plan account permission (read-only)."),
        validate: { _ = try await CopilotProvider.validate(key: $0) },
        describe: { error in
            error == .decoding
                ? AppStrings.text("GitHub has no Copilot usage report for this account. A seat paid by an organization (Copilot Business or Enterprise) is not in your personal report.")
                : nil
        })

    /// The order Settings lists them in.
    static let all: [APIKeyProvider] = [openRouter, copilot, deepSeek, moonshot, xAI]

    static func isAPIKeyProvider(_ id: String) -> Bool { all.contains { $0.id == id } }

    private static func balance(_ descriptor: BalanceDescriptor, placeholder: String? = nil, help: String,
                                rejected: String? = nil) -> APIKeyProvider {
        APIKeyProvider(id: descriptor.id, name: descriptor.name, credentialKey: descriptor.credentialKey,
                       placeholder: placeholder ?? AppStrings.format("Paste your %@ API key", descriptor.name),
                       help: help,
                       rejected: rejected ?? AppStrings.format("%@ did not accept this key.", descriptor.name),
                       validate: { _ = try await BalanceProvider.validate(descriptor, key: $0) })
    }

    func savedKey(in store: any CredentialStore = AppGroup.keychain()) -> String? {
        guard let key = try? store.read(credentialKey), !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return key
    }

    /// "sk-…a1b2": enough to tell keys apart, never the whole secret.
    static func masked(_ key: String) -> String {
        let prefix = ["sk-or-v1-", "sk-", "xai-", "github_pat_", "ghp_"].first { key.hasPrefix($0) } ?? String(key.prefix(3))
        return "\(prefix)…\(key.suffix(4))"
    }
}

/// Settings row that leads to the API-key providers, with how many are connected.
struct MoreProvidersLink: View {
    let onChanged: () -> Void
    @State private var connected = 0

    var body: some View {
        NavigationLink {
            MoreProvidersView(onChanged: onChanged)
        } label: {
            HStack {
                Label("More providers", systemImage: "key")
                Spacer(minLength: SoftTheme.Space.sm)
                if connected > 0 {
                    Text(AppStrings.format("%d connected", connected))
                        .softText(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { connected = APIKeyProvider.all.filter { $0.savedKey() != nil }.count }
    }
}

/// OpenRouter, GitHub Copilot, DeepSeek, Moonshot and xAI, each with its own key screen.
struct MoreProvidersView: View {
    @Environment(\.colorScheme) private var scheme
    let onChanged: () -> Void
    @State private var connected: Set<String> = []
    /// Debug aid for screenshots: `-open-api-key deepseek` opens that provider's key screen.
    @State private var opened: String?

    var body: some View {
        Form {
            Section {
                ForEach(APIKeyProvider.all) { provider in
                    // A destination link, not a value link: it needs no `navigationDestination(for:)` registration,
                    // which did not resolve inside the Settings sheet and left taps going nowhere.
                    NavigationLink {
                        APIKeyProviderView(provider: provider, onChanged: onChanged)
                    } label: {
                        HStack(spacing: SoftTheme.Space.md) {
                            SoftIconBadge(SoftTheme.providerSymbol(provider.id),
                                          tint: SoftTheme.providerTint(provider.id), size: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: provider.name)
                                Text(connected.contains(provider.id) ? LocalizedStringKey("Connected") : LocalizedStringKey("Not set up"))
                                    .softText(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } footer: {
                Text("Each provider appears on the dashboard once its key is saved. AI·mana reads only usage and balances through each provider's official API.")
            }
            .listRowBackground(SoftTheme.yellow.opacity(scheme == .dark ? 0.10 : 0.18))
        }
        .navigationDestination(item: $opened) { id in
            if let provider = APIKeyProvider.all.first(where: { $0.id == id }) {
                APIKeyProviderView(provider: provider, onChanged: onChanged)
            }
        }
        .scrollContentBackground(.hidden)
        .background(SoftTheme.canvas(scheme))
        .fontDesign(.rounded)
        .softText(.body)
        .navigationTitle("More providers")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            connected = Set(APIKeyProvider.all.filter { $0.savedKey() != nil }.map(\.id))
            let args = ProcessInfo.processInfo.arguments
            if opened == nil, let i = args.firstIndex(of: "-open-api-key"), args.indices.contains(i + 1),
               !Self.openedOnce {
                Self.openedOnce = true
                let id = args[i + 1]
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { opened = id }
            }
        }
    }

    @MainActor private static var openedOnce = false
}

/// One provider's key: paste and save (checked with one request first), or see the masked saved key and remove it.
struct APIKeyProviderView: View {
    @Environment(\.colorScheme) private var scheme
    let provider: APIKeyProvider
    let onChanged: () -> Void

    var body: some View {
        Form {
            APIKeySection(provider: provider, onChanged: onChanged)
                .listRowBackground(SoftTheme.providerTint(provider.id).opacity(scheme == .dark ? 0.14 : 0.22))
            if provider.id == CopilotProvider.providerID {
                CopilotPlanSection(onChanged: onChanged)
                    .listRowBackground(SoftTheme.providerTint(provider.id).opacity(scheme == .dark ? 0.14 : 0.22))
            }
        }
        .scrollContentBackground(.hidden)
        .background(SoftTheme.canvas(scheme))
        .fontDesign(.rounded)
        .softText(.body)
        .navigationTitle(Text(verbatim: provider.name))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct APIKeySection: View {
    let provider: APIKeyProvider
    let onChanged: () -> Void
    @State private var savedKey: String?
    @State private var draft = ""
    @State private var isChecking = false
    @State private var failure: String?

    private let store = AppGroup.keychain()

    var body: some View {
        Section {
            if let savedKey {
                LabeledContent("Key saved") {
                    Text(verbatim: APIKeyProvider.masked(savedKey)).font(.footnote.monospaced())
                }
                Button("Remove key", role: .destructive) { remove() }
            } else {
                SecureField(provider.placeholder, text: $draft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.password)
                    .font(.footnote.monospaced())
                    .submitLabel(.done)
                    .onSubmit { Task { await save() } }
                if isChecking {
                    Label("Checking the key…", systemImage: "hourglass").foregroundStyle(.secondary)
                } else {
                    Button("Save key") { Task { await save() } }
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            if let failure {
                Text(failure).font(.footnote).foregroundStyle(.red)
            }
        } footer: {
            Text(provider.help)
        }
        .onAppear { savedKey = provider.savedKey(in: store) }
    }

    /// Checks the key with one request before saving it, so a typo never reaches the dashboard.
    private func save() async {
        let key = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !isChecking else { return }
        isChecking = true
        failure = nil
        defer { isChecking = false }
        do {
            try await provider.validate(key)
        } catch let error as UsageProviderError {
            if let explained = provider.describe?(error) {
                failure = explained
                return
            }
            failure = switch error {
            case .unauthenticated: provider.rejected
            case .rateLimited: AppStrings.format("%@ is busy. Try again in a minute.", provider.name)
            case .decoding: AppStrings.format("%@ sent an answer AI·mana does not understand.", provider.name)
            default: AppStrings.format("Could not reach %@. Try again.", provider.name)
            }
            return
        } catch {
            failure = AppStrings.format("Could not reach %@. Try again.", provider.name)
            return
        }
        do {
            try store.write(key, for: provider.credentialKey)
        } catch {
            failure = AppStrings.text("Could not save the key in the Keychain.")
            return
        }
        draft = ""
        savedKey = key
        onChanged()
    }

    private func remove() {
        // Only claim the key is gone once the Keychain agrees; otherwise the app and widget would keep using it.
        do {
            try store.delete(provider.credentialKey)
        } catch {
            failure = AppStrings.text("Could not remove the key from the Keychain.")
            return
        }
        savedKey = nil
        failure = nil
        onChanged()
    }
}

/// The Copilot plan the reading is measured against: GitHub's API reports spend but not the included allowance.
/// Stored in the App Group defaults so the widgets use the same plan.
struct CopilotPlanSection: View {
    let onChanged: () -> Void
    @State private var plan: CopilotPlan = .pro
    @State private var customText = ""
    @State private var loaded = false
    @State private var changed = false
    @FocusState private var amountFocused: Bool

    /// Fine-grained token form with only "Plan: read" ticked, through GitHub's documented URL parameters.
    /// https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens#pre-filling-fine-grained-personal-access-token-details-using-url-parameters
    static let newTokenURL = URL(string: "https://github.com/settings/personal-access-tokens/new?name=AI%C2%B7mana%20Copilot%20usage&description=Read%20Copilot%20usage%20for%20AI%C2%B7mana&plan=read&expires_in=90")!

    var body: some View {
        Section {
            Picker("Copilot plan", selection: $plan) {
                ForEach(CopilotPlan.allCases) { option in
                    Text(verbatim: option.title()).tag(option)
                }
            }
            if plan == .custom {
                LabeledContent("Included each month (US$)") {
                    TextField("0.00", text: $customText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .focused($amountFocused)
                        .frame(maxWidth: 110)
                }
            }
            Link(destination: Self.newTokenURL) {
                Label("Create a token on GitHub", systemImage: "arrow.up.right.square")
            }
        } header: {
            Text("Plan")
        } footer: {
            Text(footer)
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            let saved = CopilotPreferences.allowance()
            plan = saved.plan
            customText = saved.customUSD.map { $0.formatted(.number.precision(.fractionLength(0...2))) } ?? ""
        }
        .onChange(of: plan) { _, new in
            guard loaded else { return }
            CopilotPreferences.setPlan(new)
            changed = true
        }
        .onChange(of: customText) { _, new in
            guard loaded else { return }
            CopilotPreferences.setCustomUSD(Self.amount(new))
            changed = true
        }
        // One refresh when leaving, not one per keystroke.
        .onDisappear { if changed { changed = false; onChanged() } }
    }

    private var footer: String {
        let resets = AppStrings.text("GitHub's API reports what you spend, not your allowance, so AI·mana measures it against this plan. Included credits reset on the 1st of each month at 00:00 UTC. A seat paid by an organization is not in your personal report.")
        guard let credits = plan.includedCredits else {
            return AppStrings.text("Enter the dollar value of the AI credits included each month (1 credit = US$0.01).") + " " + resets
        }
        let count = credits.formatted(.number.precision(.fractionLength(0)))
        let dollars = (credits / 100).formatted(.currency(code: "USD").precision(.fractionLength(0)))
        return AppStrings.format("Includes %@ AI credits a month (%@).", count, dollars) + " " + resets
    }

    /// "25", "25.5" or "25,5"; nil for anything else or a non-positive amount.
    static func amount(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned), value.isFinite, value > 0 else { return nil }
        return value
    }
}
