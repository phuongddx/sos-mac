import Foundation
import Testing
@testable import CleanCore

struct CloudHTTPClientTests {
    @Test func retriesOn429ThenSucceeds() async throws {
        let token = UUID().uuidString
        let session = StubURLProtocol.makeSession(token: token, responses: [
            .init(statusCode: 429, data: Data()),
            .init(statusCode: 429, data: Data()),
            .init(statusCode: 200, data: "ok".data(using: .utf8)!)
        ])

        let request = URLRequest(url: URL(string: "https://example.com/test")!)
        let (data, response) = try await CloudHTTPClient.send(request, session: session, initialDelay: 0.01)

        #expect(response.statusCode == 200)
        #expect(String(data: data, encoding: .utf8) == "ok")
        #expect(StubURLProtocol.requestCount(forToken: token) == 3) // 2 retries + final success
    }

    @Test func givesUpAfterMaxAttemptsAndThrowsRateLimited() async throws {
        let token = UUID().uuidString
        let session = StubURLProtocol.makeSession(
            token: token,
            responses: Array(repeating: .init(statusCode: 429, data: Data()), count: 10)
        )

        let request = URLRequest(url: URL(string: "https://example.com/test")!)

        await #expect(throws: CloudProviderError.rateLimited) {
            _ = try await CloudHTTPClient.send(request, session: session, maxAttempts: 3, initialDelay: 0.01)
        }
        #expect(StubURLProtocol.requestCount(forToken: token) == 3)
    }

    @Test func nonRetryableErrorThrowsImmediatelyWithoutRetrying() async throws {
        let token = UUID().uuidString
        let session = StubURLProtocol.makeSession(token: token, responses: [.init(statusCode: 404, data: Data())])

        let request = URLRequest(url: URL(string: "https://example.com/test")!)

        await #expect(throws: CloudProviderError.requestFailed(statusCode: 404)) {
            _ = try await CloudHTTPClient.send(request, session: session, initialDelay: 0.01)
        }
        #expect(StubURLProtocol.requestCount(forToken: token) == 1) // no retry for a plain 404
    }

    @Test func retriesOnServerErrorThenSucceeds() async throws {
        let token = UUID().uuidString
        let session = StubURLProtocol.makeSession(token: token, responses: [
            .init(statusCode: 503, data: Data()),
            .init(statusCode: 200, data: "recovered".data(using: .utf8)!)
        ])

        let request = URLRequest(url: URL(string: "https://example.com/test")!)
        let (data, response) = try await CloudHTTPClient.send(request, session: session, initialDelay: 0.01)

        #expect(response.statusCode == 200)
        #expect(String(data: data, encoding: .utf8) == "recovered")
    }
}
