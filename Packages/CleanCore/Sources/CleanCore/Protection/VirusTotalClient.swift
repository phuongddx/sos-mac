import Foundation

public enum VirusTotalError: Error, Sendable, Equatable {
    /// No API key configured — every call fails closed rather than
    /// attempting a doomed request, same pattern as `CloudProviderConfig`.
    case notConfigured
    case notFound
    case requestFailed(statusCode: Int)
    case rateLimited
}

public struct VirusTotalVerdict: Sendable, Equatable {
    public let maliciousCount: Int
    public let suspiciousCount: Int
    public let totalEngines: Int

    public var isFlagged: Bool { maliciousCount > 0 }

    public init(maliciousCount: Int, suspiciousCount: Int, totalEngines: Int) {
        self.maliciousCount = maliciousCount
        self.suspiciousCount = suspiciousCount
        self.totalEngines = totalEngines
    }
}

/// A real VirusTotal API v3 hash-lookup client (docs:
/// https://docs.virustotal.com/reference/file-info) — hash lookup only,
/// never a file upload. Uploading whole user files to a third party is a
/// materially different privacy trade-off than looking up a hash and isn't
/// something this app does without separate, explicit consent. Supplementary
/// only: `ProtectionScanner` never depends on this client, so Protection
/// stays fully functional offline.
public struct VirusTotalClient: Sendable {
    /// A real, developer-obtained VirusTotal API key — not fabricatable
    /// here. Empty by default, which `lookup` treats as `.notConfigured`.
    public struct Config: Sendable {
        public let apiKey: String

        public init(apiKey: String = "") {
            self.apiKey = apiKey
        }

        public var isConfigured: Bool { !apiKey.isEmpty }
    }

    private let config: Config
    private let session: URLSession
    private let baseURL: URL

    public init(
        config: Config,
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://www.virustotal.com/api/v3/files")!
    ) {
        self.config = config
        self.session = session
        self.baseURL = baseURL
    }

    public func lookup(sha256: String) async throws -> VirusTotalVerdict {
        guard config.isConfigured else { throw VirusTotalError.notConfigured }

        var request = URLRequest(url: baseURL.appendingPathComponent(sha256))
        request.httpMethod = "GET"
        request.setValue(config.apiKey, forHTTPHeaderField: "x-apikey")

        let (data, response): (Data, HTTPURLResponse)
        do {
            (data, response) = try await ProtectionHTTPClient.send(request, session: session)
        } catch ProtectionNetworkError.rateLimited {
            throw VirusTotalError.rateLimited
        } catch ProtectionNetworkError.requestFailed(let statusCode) {
            throw VirusTotalError.requestFailed(statusCode: statusCode)
        }

        if response.statusCode == 404 {
            throw VirusTotalError.notFound
        }
        guard (200..<300).contains(response.statusCode) else {
            throw VirusTotalError.requestFailed(statusCode: response.statusCode)
        }

        let report = try JSONDecoder().decode(FileReportResponse.self, from: data)
        let stats = report.data.attributes.lastAnalysisStats
        let total = stats.malicious + stats.suspicious + stats.harmless + stats.undetected + stats.timeout
        return VirusTotalVerdict(maliciousCount: stats.malicious, suspiciousCount: stats.suspicious, totalEngines: total)
    }
}

private struct FileReportResponse: Decodable {
    let data: FileData

    struct FileData: Decodable {
        let attributes: Attributes
    }

    struct Attributes: Decodable {
        let lastAnalysisStats: Stats

        enum CodingKeys: String, CodingKey {
            case lastAnalysisStats = "last_analysis_stats"
        }
    }

    struct Stats: Decodable {
        let malicious: Int
        let suspicious: Int
        let harmless: Int
        let undetected: Int
        let timeout: Int
    }
}
