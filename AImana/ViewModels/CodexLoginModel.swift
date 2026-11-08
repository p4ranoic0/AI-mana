import AImanaCore
import Foundation
import Observation

@MainActor
@Observable
final class CodexLoginModel {
    enum Phase: Equatable {
        case idle, requestingCode
        /// Device code shown; the app is polling until the user approves it on the web page.
        case waitingForApproval(code: String, url: URL)
        /// Browser fallback: waiting for the user to paste Safari's final address.
        case waitingForRedirect
        case working
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var isSignedIn = Services.codexTokens.isSignedIn
    var pastedRedirect = ""
    private var request: CodexLoginRequest?
    private var polling: Task<Void, Never>?

    /// Asks OpenAI for a one-time code and polls in the background until it is approved or expires.
    func startDeviceLogin(onSignedIn: @escaping () -> Void) {
        polling?.cancel()
        request = nil
        phase = .requestingCode
        polling = Task { [weak self] in
            let transport = URLSessionTransport()
            do {
                let device = try await CodexOAuth.requestDeviceCode(transport: transport)
                self?.phase = .waitingForApproval(code: device.userCode, url: device.verificationURL)
                let session = try await CodexOAuth.completeDeviceLogin(device, transport: transport)
                await self?.finish(session, onSignedIn: onSignedIn)
            } catch is CancellationError {
                return
            } catch CodexLoginError.deviceCodeUnavailable {
                self?.phase = .failed(AppStrings.text("Device code sign-in is not available for this account. Turn on device code authorization in ChatGPT's security settings, or use the browser sign-in."))
            } catch CodexLoginError.expired {
                self?.phase = .failed(AppStrings.text("The code expired before it was approved. Start the sign-in again."))
            } catch {
                guard !Task.isCancelled else { return }
                self?.phase = .failed(AppStrings.text("Could not sign in to ChatGPT. Check your connection and try again."))
            }
        }
    }

    func cancel() {
        polling?.cancel()
        polling = nil
        request = nil
        pastedRedirect = ""
        phase = .idle
    }

    /// Fallback: starts a fresh PKCE browser login and returns the page to open.
    func beginBrowserLogin() -> URL {
        polling?.cancel()
        let new = CodexOAuth.beginBrowserLogin()
        request = new
        pastedRedirect = ""
        phase = .waitingForRedirect
        return new.url
    }

    func connectBrowserLogin(onSignedIn: @escaping () -> Void) async {
        guard let request else { return }
        phase = .working
        do {
            let code = try CodexOAuth.parsePastedRedirect(pastedRedirect, expectedState: request.state)
            let session = try await CodexOAuth.exchange(code: code, request: request, transport: URLSessionTransport())
            await finish(session, onSignedIn: onSignedIn)
        } catch {
            phase = .failed(AppStrings.text("That address did not work. Open the sign-in page again and paste the new address."))
        }
    }

    private func finish(_ session: CodexSession, onSignedIn: () -> Void) async {
        do {
            try await Services.codexTokens.save(session)
        } catch {
            phase = .failed(AppStrings.text("Could not save the sign-in to the Keychain."))
            return
        }
        polling = nil
        request = nil
        pastedRedirect = ""
        isSignedIn = true
        phase = .idle
        onSignedIn()
    }

    func signOut(onChange: () -> Void) async {
        cancel()
        do { try await Services.codexTokens.signOut() } catch {
            phase = .failed(AppStrings.text("Couldn't remove the sign-in from this device. Try again."))
            return
        }
        isSignedIn = false
        onChange()
    }
}
