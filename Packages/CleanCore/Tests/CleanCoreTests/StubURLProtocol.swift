import Foundation

/// A queue-driven `URLProtocol` stub for testing HTTP call sites without
/// hitting real provider APIs (which would burn quota and risk flaky CI, per
/// the Phase 6 spec's own test guidance).
///
/// State is keyed per-test by a token embedded in a request header, NOT a
/// single shared global queue — Swift Testing runs @Test methods (and
/// different @Suite types) concurrently by default, and a bare shared static
/// queue caused real cross-test races in practice (confirmed: two suites
/// both using StubURLProtocol produced generic NSURLErrorDomain -1 failures
/// from one test draining another's queue). `@Suite(.serialized)` alone
/// doesn't fix this — it only serializes within one suite, not across
/// suites running concurrently with each other.
final class StubURLProtocol: URLProtocol {
    struct StubResponse {
        let statusCode: Int
        let data: Data
    }

    private static let lock = NSLock()
    // Protected by `lock`, not actor isolation — every access below takes
    // the lock first, so this is safe despite not being Sendable-checked.
    nonisolated(unsafe) private static var queuesByToken: [String: [StubResponse]] = [:]
    nonisolated(unsafe) private static var countsByToken: [String: Int] = [:]

    private static let tokenHeader = "X-Test-Stub-Token"

    /// Creates a session scoped to its own isolated stub state, identified
    /// by `token` (pass a fresh `UUID().uuidString` per test).
    static func makeSession(token: String, responses: [StubResponse]) -> URLSession {
        lock.lock()
        queuesByToken[token] = responses
        countsByToken[token] = 0
        lock.unlock()

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        config.httpAdditionalHeaders = [tokenHeader: token]
        return URLSession(configuration: config)
    }

    static func requestCount(forToken token: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return countsByToken[token] ?? 0
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let token = request.value(forHTTPHeaderField: Self.tokenHeader) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }

        Self.lock.lock()
        Self.countsByToken[token, default: 0] += 1
        var queue = Self.queuesByToken[token] ?? []
        guard !queue.isEmpty else {
            Self.lock.unlock()
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        let stub = queue.removeFirst()
        Self.queuesByToken[token] = queue
        Self.lock.unlock()

        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.com")!,
            statusCode: stub.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
