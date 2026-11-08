import AImanaCore
import SwiftUI

/// The notice the user must accept before this iPhone uses a provider's undocumented usage endpoint. Accepting
/// records the consent (`DirectAccessConsent`); without it a stored session is never used.
struct DirectAccessNoticeSheet: View {
    let provider: DirectProvider
    let onAccept: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var title: LocalizedStringKey {
        provider == .claude ? "Read Claude usage directly?" : "Read Codex usage directly?"
    }

    private var notice: LocalizedStringKey {
        switch provider {
        case .claude:
            "Off by default. When on, AI·mana reads your Claude usage from an endpoint that is not a public API. Anthropic's Claude Code terms prohibit third-party apps from offering Claude.ai sign-in or storing its tokens. Turning this on is your decision; the provider has not authorized it, and it could limit or suspend your account. The endpoint can change or stop working at any time; AI·mana then falls back to the relay. You will sign in with your own account on this device. The session is stored in this device's Keychain, shared with nobody, and signing out deletes it."
        case .codex:
            "Off by default. When on, AI·mana reads your ChatGPT usage from an endpoint that is not a public API. OpenAI's terms restrict programmatic access to its services. Turning this on is your decision; the provider has not authorized it, and it could limit or suspend your account. The endpoint can change or stop working at any time; AI·mana then falls back to the relay. You will sign in with your own account on this device. The session is stored in this device's Keychain, shared with nobody, and signing out deletes it."
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(notice).font(.body).frame(maxWidth: .infinity, alignment: .leading).padding()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: SoftTheme.Space.sm) {
                    Button {
                        onAccept()
                        dismiss()
                    } label: {
                        Text("Accept and continue").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                .padding()
                .background(.bar)
            }
        }
        .interactiveDismissDisabled()   // accepting needs the button, not a swipe
    }
}

/// The permanent "Unofficial" tag next to a direct-access section's title.
struct UnofficialTag: View {
    var body: some View {
        Text("Unofficial").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .overlay(Capsule().stroke(.secondary.opacity(0.5)))
    }
}
