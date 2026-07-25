import Foundation

/// Presents the OS-native OAuth browser sheet and returns the redirect URL
/// once the provider calls back. The real conformance (backed by
/// `ASWebAuthenticationSession`, per Phase 6's own instruction not to build
/// a custom embedded web view) lives in the App target, since presenting it
/// needs a live window anchor — CleanCore stays UI-free and testable by
/// depending only on this protocol.
public protocol OAuthWebSessionPresenting: Sendable {
    func present(url: URL, callbackURLScheme: String) async throws -> URL
}
