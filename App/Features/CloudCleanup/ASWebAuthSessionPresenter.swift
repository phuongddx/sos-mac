import AuthenticationServices
import AppKit
import CleanCore

/// The real `OAuthWebSessionPresenting` conformance — uses
/// `ASWebAuthenticationSession`, the standard macOS-native OAuth UI (per
/// Phase 6's own instruction not to build a custom embedded web view).
/// Lives in the App target, not CleanCore, because presenting it needs a
/// live `NSWindow` anchor.
@MainActor
final class ASWebAuthSessionPresenter: NSObject, OAuthWebSessionPresenting, ASWebAuthenticationPresentationContextProviding {
    private var activeSession: ASWebAuthenticationSession?

    func present(url: URL, callbackURLScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackURLScheme) { callbackURL, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: CloudProviderError.requestFailed(statusCode: -1))
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.activeSession = session
            session.start()
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // ASWebAuthenticationPresentationContextProviding isn't documented
        // by Apple as guaranteed-main-thread (in practice it always is,
        // since it's paired with AppKit UI presentation), but
        // MainActor.assumeIsolated traps if that assumption is ever wrong —
        // a hard crash, unlike everything else in this phase which fails
        // closed gracefully. Falling back to a synchronous main-thread hop
        // tolerates an off-main callback instead.
        if Thread.isMainThread {
            return MainActor.assumeIsolated { Self.resolveAnchor() }
        }
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated { Self.resolveAnchor() }
        }
    }

    @MainActor
    private static func resolveAnchor() -> ASPresentationAnchor {
        NSApplication.shared.windows.first { $0.isKeyWindow } ?? NSApplication.shared.windows.first ?? NSWindow()
    }
}
