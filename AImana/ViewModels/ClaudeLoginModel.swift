import AImanaCore
import Foundation
import Observation

@MainActor
@Observable
final class ClaudeLoginModel {
    enum Phase: Equatable { case idle, waitingForCode, working, failed(String) }

    private(set) var phase: Phase = .idle
    private(set) var isSignedIn = Services.claudeTokens.isSignedIn
    var pastedCode = ""
    private var request: ClaudeLoginRequest?

    /// Starts a fresh PKCE login and returns the page to open in the browser.
    func begin() -> URL {
        let new = ClaudeOAuth.beginLogin()
        request = new
        pastedCode = ""
        phase = .waitingForCode
        return new.url
    }

    func connect(onSignedIn: @escaping () -> Void) async {
        guard let request else { return }
        phase = .working
        do {
            let code = try ClaudeOAuth.parsePastedCode(pastedCode, expectedState: request.state)
            let session = try await ClaudeOAuth.exchange(code: code, request: request, transport: URLSessionTransport())
            try await Services.claudeTokens.save(session)
            self.request = nil
            pastedCode = ""
            isSignedIn = true
            phase = .idle
            onSignedIn()
        } catch {
            phase = .failed(AppStrings.text("That code did not work. Open the sign-in page again and paste the new code."))
        }
    }

    func signOut(onChange: () -> Void) async {
        do { try await Services.claudeTokens.signOut() } catch {
            phase = .failed(AppStrings.text("Couldn't remove the sign-in from this device. Try again."))
            return
        }
        isSignedIn = false
        phase = .idle
        onChange()
    }
}
