import Foundation

public struct AppcastCheckResult: Sendable, Equatable {
    public let latestVersion: String
    public let isUpdateAvailable: Bool
}

/// Checks a Sparkle appcast feed for apps that expose `SUFeedURL` — this is
/// deliberately scoped to Sparkle-based apps only. There's no official
/// mechanism to auto-update arbitrary third-party apps, so reimplementing
/// every vendor's own updater is out of scope.
public enum SparkleAppcastChecker {
    public static func checkForUpdate(
        feedURL: URL,
        installedVersion: String,
        urlSession: URLSession = .shared
    ) async throws -> AppcastCheckResult? {
        let (data, _) = try await urlSession.data(from: feedURL)
        guard let latestVersion = parseLatestVersion(from: data) else { return nil }
        let isNewer = latestVersion.compare(installedVersion, options: .numeric) == .orderedDescending
        return AppcastCheckResult(latestVersion: latestVersion, isUpdateAvailable: isNewer)
    }

    static func parseLatestVersion(from data: Data) -> String? {
        let delegate = FirstEnclosureVersionDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.firstVersion
    }
}

/// Sparkle's appcast lists releases newest-first, so the first `<enclosure>`
/// carrying a version attribute is the current release — stop parsing there
/// rather than reading the whole feed.
private final class FirstEnclosureVersionDelegate: NSObject, XMLParserDelegate {
    private(set) var firstVersion: String?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard firstVersion == nil, elementName == "enclosure" else { return }
        if let version = attributeDict["sparkle:shortVersionString"] ?? attributeDict["sparkle:version"] {
            firstVersion = version
            parser.abortParsing()
        }
    }
}
