import Foundation

/// Centralizes exponential-backoff retry for every cloud provider's HTTP
/// calls — never a naive tight-loop `while (hasMore)` against a real API
/// with rate limits.
public enum CloudHTTPClient {
    public static func send(
        _ request: URLRequest,
        session: URLSession = .shared,
        maxAttempts: Int = 5,
        initialDelay: TimeInterval = 1
    ) async throws -> (Data, HTTPURLResponse) {
        var attempt = 0
        var delay: TimeInterval = initialDelay

        while true {
            attempt += 1
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw CloudProviderError.requestFailed(statusCode: -1)
            }

            let shouldRetry = (httpResponse.statusCode == 429 || httpResponse.statusCode >= 500)
            if shouldRetry, attempt < maxAttempts {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                delay *= 2
                continue
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                if httpResponse.statusCode == 429 {
                    throw CloudProviderError.rateLimited
                }
                throw CloudProviderError.requestFailed(statusCode: httpResponse.statusCode)
            }

            return (data, httpResponse)
        }
    }
}
