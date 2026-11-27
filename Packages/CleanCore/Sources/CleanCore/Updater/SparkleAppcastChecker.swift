import Foundation

/// What a Sparkle appcast's newest release carries. An `<enclosure>` may name the marketing
/// version (`sparkle:shortVersionString`), the build number (`sparkle:version`), or both —
/// they are different namespaces and are never compared with each other.
public struct AppcastRelease: Sendable, Equatable {
    public let shortVersion: String?
    public let buildVersion: String?

    public init(shortVersion: String? = nil, buildVersion: String? = nil) {
        self.shortVersion = shortVersion
        self.buildVersion = buildVersion
    }

    /// The comparable pair for an app: the feed's marketing version against the installed
    /// marketing version, else the feed's build number against the installed build. `nil`
    /// when neither pair is complete — the caller must read that as "couldn't check", never
    /// guess a verdict (fail closed).
    public func verdict(installedVersion: String?, installedBuild: String?) -> AppcastVerdict? {
        if let short = shortVersion, let installed = installedVersion {
            return AppcastVerdict(latestVersion: short, installedBasis: installed)
        }
        if let build = buildVersion, let installed = installedBuild {
            return AppcastVerdict(latestVersion: build, installedBasis: installed)
        }
        return nil
    }
}

/// A feed version and the installed version it is comparable with (same namespace).
public struct AppcastVerdict: Sendable, Equatable {
    public let latestVersion: String
    public let installedBasis: String

    public init(latestVersion: String, installedBasis: String) {
        self.latestVersion = latestVersion
        self.installedBasis = installedBasis
    }

    public var isUpdateAvailable: Bool {
        AppVersion(latestVersion) > AppVersion(installedBasis)
    }
}

/// Checks a Sparkle appcast feed for apps that expose `SUFeedURL` — this is
/// deliberately scoped to Sparkle-based apps only. There's no official
/// mechanism to auto-update arbitrary third-party apps, so reimplementing
/// every vendor's own updater is out of scope.
public enum SparkleAppcastChecker {
    /// The newest release the feed lists, `nil` when no enclosure carries a version. It does
    /// not compare anything: which installed version it is comparable with depends on the
    /// app (`AppcastRelease.verdict`).
    public static func latestRelease(
        feedURL: URL,
        urlSession: URLSession = .shared
    ) async throws -> AppcastRelease? {
        let (data, _) = try await urlSession.data(from: feedURL)
        return parseLatestRelease(from: data)
    }

    static func parseLatestRelease(from data: Data) -> AppcastRelease? {
        let delegate = FirstEnclosureVersionDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.release
    }
}

/// Sparkle's appcast lists releases newest-first, so the first `<enclosure>`
/// carrying a version attribute is the current release — stop parsing there
/// rather than reading the whole feed.
private final class FirstEnclosureVersionDelegate: NSObject, XMLParserDelegate {
    private(set) var release: AppcastRelease?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard release == nil, elementName == "enclosure" else { return }
        let short = attributeDict["sparkle:shortVersionString"]
        let build = attributeDict["sparkle:version"]
        guard short != nil || build != nil else { return }
        release = AppcastRelease(shortVersion: short, buildVersion: build)
        parser.abortParsing()
    }
}
