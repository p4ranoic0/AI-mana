import AImanaCore
import RelayKit
import SwiftUI

/// Claude and Codex read straight from each provider with the session the CLI keeps on this Mac. Off by default;
/// turning one on needs the notice accepted (`DirectAccessConsent`), turning it off withdraws the consent.
struct DirectSourcesSection: View {
    let controller: RelayController
    @State private var pending: DirectProvider?
    @State private var consentVersion = 0   // re-reads the consent after the dialog

    nonisolated static let consent = DirectAccessConsent(defaults: .standard)

    /// Asked by each direct provider on every fetch, so turning one off stops it mid-publish.
    nonisolated static func isAllowed(_ providerID: String) -> Bool {
        DirectProvider(rawValue: providerID).map(consent.isGranted) ?? false
    }

    private func isOn(_ provider: DirectProvider) -> Bool {
        _ = consentVersion
        return controller.sourceEnabled[provider.rawValue] == true && Self.consent.isGranted(provider)
    }

    private func binding(_ provider: DirectProvider) -> Binding<Bool> {
        Binding(get: { isOn(provider) }, set: { on in
            if on {
                pending = provider
            } else {
                Self.consent.revoke(provider)
                controller.setSource(provider.rawValue, enabled: false)
                consentVersion += 1
            }
        })
    }

    var body: some View {
        Section {
            Toggle(isOn: binding(.claude)) {
                HStack { Text("Claude: read usage directly"); Text("Unofficial").font(.caption2).foregroundStyle(.secondary) }
            }
            Toggle(isOn: binding(.codex)) {
                HStack { Text("Codex: read usage directly"); Text("Unofficial").font(.caption2).foregroundStyle(.secondary) }
            }
            Text("Adds per-model limits and credits, and keeps the iPhone updated without the statusline. Off by default.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        } header: {
            Text("Direct access")
        }
        .alert(pending == .codex ? "Read Codex usage directly?" : "Read Claude usage directly?",
               isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
               presenting: pending) { provider in
            Button("Accept and continue") {
                Self.consent.grant(provider)
                controller.setSource(provider.rawValue, enabled: true)
                consentVersion += 1
            }
            Button("Cancel", role: .cancel) {}
        } message: { provider in
            Text(provider == .claude ? Self.claudeNotice : Self.codexNotice)
        }
    }

    static let claudeNotice: LocalizedStringKey = "Off by default. When on, AI·mana reads the session that Claude Code keeps in your Keychain or ~/.claude on this Mac and calls a usage endpoint that is not a public API. Anthropic's Claude Code terms prohibit third-party apps from using Claude.ai credentials. Turning this on is your decision; the provider has not authorized it. AI·mana only reads the session; it never changes or renews it itself. If the endpoint fails, AI·mana uses the local data."
    static let codexNotice: LocalizedStringKey = "Off by default. When on, AI·mana reads the session that Codex keeps in ~/.codex/auth.json on this Mac and calls a usage endpoint that is not a public API. OpenAI's terms restrict programmatic access to its services. Turning this on is your decision; the provider has not authorized it. AI·mana only reads the session; it never changes or renews it itself. If the endpoint fails, AI·mana uses the local data."
}
