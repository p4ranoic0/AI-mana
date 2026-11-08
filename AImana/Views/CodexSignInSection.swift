// Off until the user accepts the notice (`DirectAccessNoticeSheet`); the relay keeps working without it.
import AImanaCore
import SwiftUI
import UIKit

/// Lets this iPhone sign in to ChatGPT on its own, so Codex usage keeps updating without the Mac.
struct CodexSignInSection: View {
    let onChanged: () -> Void
    @State private var model = CodexLoginModel()
    @State private var web = WebSignIn()
    @Environment(\.openURL) private var openURL
    @State private var consented = Services.consent.isGranted(.codex)
    @State private var notice: NoticeAction?

    private enum NoticeAction: Identifiable { case device, browser, enable; var id: Self { self } }

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
                switch model.phase {
                case .requestingCode:
                    ProgressView()
                case .waitingForApproval(let code, let url):
                    Text(code)
                        .font(.title2.monospaced().weight(.semibold))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity)
                    Button("Open the ChatGPT page again") { openDevicePage(code: code, url: url) }
                    Label("Waiting for approval…", systemImage: "hourglass").foregroundStyle(.secondary)
                    Button("Cancel", role: .cancel) { model.cancel() }
                case .waitingForRedirect, .working:
                    TextField("Paste the address from Safari", text: $model.pastedRedirect, axis: .vertical)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .font(.footnote.monospaced())
                    Button("Connect") { Task { await model.connectBrowserLogin(onSignedIn: onChanged) } }
                        .disabled(model.pastedRedirect.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  || model.phase == .working)
                    Button("Cancel", role: .cancel) { model.cancel() }
                case .idle, .failed:
                    Button("Sign in with ChatGPT") { consented ? run(.device) : (notice = .device) }
                    Button("Use browser sign-in instead") { consented ? run(.browser) : (notice = .browser) }
                        .font(.footnote)
                }
            }
            // Also shown while signed in: a sign-out that could not delete the session reports it here.
            if case .failed(let message) = model.phase {
                Text(message).font(.footnote).foregroundStyle(.red)
            }
        } header: {
            HStack { Text("ChatGPT on this iPhone"); UnofficialTag() }
        } footer: {
            switch model.phase {
            case .waitingForRedirect:
                Text("After you approve, Safari shows a page that cannot be reached. Copy that page's full address and paste it here.")
            case .waitingForApproval:
                Text("The code is already copied. Paste it on the ChatGPT page and approve; this page closes by itself.")
            default:
                Text("A separate session from your computer's Codex login, stored in the iOS Keychain.")
            }
        }
        .onChange(of: model.phase) { _, phase in
            switch phase {
            case .waitingForApproval(let code, let url): openDevicePage(code: code, url: url)
            case .requestingCode: break
            default: web.close()
            }
        }
        .onDisappear { web.close() }
        .sheet(item: $notice) { action in
            DirectAccessNoticeSheet(provider: .codex) {
                Services.consent.grant(.codex)
                consented = true
                run(action)
            }
        }
    }

    private func run(_ action: NoticeAction) {
        switch action {
        case .device: model.startDeviceLogin(onSignedIn: onChanged)
        case .browser: openURL(model.beginBrowserLogin())
        case .enable: onChanged()
        }
    }

    /// Signing out also withdraws the consent: the next sign-in shows the notice again.
    private func signOut() async {
        await model.signOut(onChange: onChanged)
        guard !model.isSignedIn else { return }
        PhoneDirectAccess.revoke(.codex, consent: Services.consent)
        consented = false
    }

    /// Copies the code first so the user only has to paste it on ChatGPT's page.
    private func openDevicePage(code: String, url: URL) {
        UIPasteboard.general.string = code
        web.open(url) {}
    }
}
