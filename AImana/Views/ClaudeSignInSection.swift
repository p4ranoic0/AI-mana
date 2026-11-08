// Anthropic's terms do not allow third-party apps to offer Claude.ai login: this section is off until the user
// accepts the notice (`DirectAccessNoticeSheet`), and the relay keeps working without it.
import AImanaCore
import SwiftUI

/// Lets this iPhone sign in to Claude on its own, so usage keeps updating without the Mac.
struct ClaudeSignInSection: View {
    let onChanged: () -> Void
    @State private var model = ClaudeLoginModel()
    @State private var web = WebSignIn()
    @State private var consented = Services.consent.isGranted(.claude)
    @State private var notice: NoticeAction?

    private enum NoticeAction: Identifiable { case signIn, enable; var id: Self { self } }

    var body: some View {
        Section {
            if model.isSignedIn && !consented {
                // A session saved by an earlier build: unused until the user accepts the notice.
                Button("Turn on direct access") { notice = .enable }
                Button("Sign out", role: .destructive) { Task { await signOut() } }
            } else if model.isSignedIn {
                Text("Signed in on this iPhone")
                Button("Sign out", role: .destructive) { Task { await signOut() } }
            } else {
                Button(model.phase == .idle ? "Sign in with Claude" : "Open the sign-in page again") {
                    if consented { web.open(model.begin()) {} } else { notice = .signIn }
                }
                if model.phase != .idle {
                    // PasteButton reads the clipboard without the system's paste permission prompt.
                    PasteButton(payloadType: String.self) { strings in
                        guard let code = strings.first else { return }
                        Task { @MainActor in
                            model.pastedCode = code
                            await model.connect(onSignedIn: onChanged)
                        }
                    }
                    .disabled(model.phase == .working)
                    if model.phase == .working { ProgressView() }
                }
            }
            // Also shown while signed in: a sign-out that could not delete the session reports it here.
            if case .failed(let message) = model.phase {
                Text(message).font(.footnote).foregroundStyle(.red)
            }
        } header: {
            HStack { Text("Claude on this iPhone"); UnofficialTag() }
        } footer: {
            if model.phase == .idle {
                Text("A separate session from your computer's that can only read usage. It is stored in the iOS Keychain.")
            } else {
                Text("Approve access, copy the code the page shows, close the page, then tap Paste.")
            }
        }
        .sheet(item: $notice) { action in
            DirectAccessNoticeSheet(provider: .claude) {
                Services.consent.grant(.claude)
                consented = true
                if action == .signIn { web.open(model.begin()) {} } else { onChanged() }
            }
        }
    }

    /// Signing out also withdraws the consent: the next sign-in shows the notice again.
    private func signOut() async {
        await model.signOut(onChange: onChanged)
        guard !model.isSignedIn else { return }
        PhoneDirectAccess.revoke(.claude, consent: Services.consent)
        consented = false
    }
}
