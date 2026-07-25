import Foundation

public enum ProtectionNetworkError: Error, Sendable, Equatable {
    case requestFailed(statusCode: Int)
    case rateLimited
}

/// Shared exponential-backoff HTTP retry for Protection's two network
/// clients (`VirusTotalClient`, `SignatureUpdateChecker`) — same "never a
/// naive tight retry loop against a rate-limited API" rule as Cloud
/// Cleanup's `CloudHTTPClient`, kept as its own type since Protection has no
/// reason to depend on Cloud's error domain. Deliberately handles only the
/// retry policy (429/5xx) — success-code validation (2xx, or a caller's own
/// "expected" non-2xx like a 404 miss) stays with each caller, since that
/// varies per endpoint.
public enum ProtectionHTTPClient {
    public static func send(
        _ request: URLRequest,
        session: URLSession = .shared,
        maxAttempts: Int = 5,
        initialDelay: TimeInterval = 1
    ) async throws -> (Data, HTTPURLResponse) {
        var attempt = 0
        var delay = initialDelay

        while true {
            attempt += 1
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ProtectionNetworkError.requestFailed(statusCode: -1)
            }

            let shouldRetry = (httpResponse.statusCode == 429 || httpResponse.statusCode >= 500)
            if shouldRetry, attempt < maxAttempts {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                delay *= 2
                continue
            }
            if httpResponse.statusCode == 429 {
                throw ProtectionNetworkError.rateLimited
            }

            return (data, httpResponse)
        }
    }
}
