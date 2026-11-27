import Foundation
import Testing
@testable import CleanCore

@Suite("AppVersion")
struct AppVersionTests {

    @Test("the comparator table", arguments: [
        // (left, right, expected ordering of left against right)
        ("1.0", "1.0.0", ComparisonResult.orderedSame),
        ("1.0.0", "1.0", .orderedSame),
        ("1.10", "1.9", .orderedDescending),
        ("1.9", "1.10", .orderedAscending),
        ("1.2", "1.2.1", .orderedAscending),
        ("2", "1.9.9", .orderedDescending),
        ("1250", "1249", .orderedDescending),
        ("1.09", "1.9", .orderedSame),
        ("1.0.0.1", "1.0", .orderedDescending),
        ("20241127123456789012", "20241127123456789011", .orderedDescending),
        ("9", "10", .orderedAscending),
    ])
    func comparatorTable(left: String, right: String, expected: ComparisonResult) {
        let l = AppVersion(left)
        let r = AppVersion(right)
        switch expected {
        case .orderedSame:
            #expect(l == r)
            #expect(!(l < r) && !(l > r))
        case .orderedAscending:
            #expect(l < r)
            #expect(!(l > r))
        case .orderedDescending:
            #expect(l > r)
            #expect(!(l < r))
        }
    }

    @Test("non-numeric segments compare lexicographically (documented approximation)")
    func nonNumericSegments() {
        #expect(AppVersion("1.0b2") > AppVersion("1.0b1"))
        #expect(AppVersion("1.0rc1") > AppVersion("1.0b9"))
        #expect(AppVersion("1.0b1") == AppVersion("1.0b1"))
        // Approximation: a pre-release suffix sorts after the plain release.
        #expect(AppVersion("1.0b1") > AppVersion("1.0"))
    }

    @Test("only a strictly greater feed version claims an update")
    func onlyStrictlyGreaterIsAnUpdate() {
        #expect(AppcastVerdict(latestVersion: "1.10", installedBasis: "1.9").isUpdateAvailable)
        #expect(!AppcastVerdict(latestVersion: "1.0.0", installedBasis: "1.0").isUpdateAvailable)
        #expect(!AppcastVerdict(latestVersion: "1.9", installedBasis: "1.10").isUpdateAvailable)
        #expect(!AppcastVerdict(latestVersion: "3.0", installedBasis: "3.1").isUpdateAvailable)
    }
}

@Suite("SparkleAppcastChecker")
struct SparkleAppcastCheckerTests {

    private func appcast(_ enclosures: String) -> Data {
        Data("""
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
          <channel>
            \(enclosures)
          </channel>
        </rss>
        """.utf8)
    }

    @Test("reads both the marketing version and the build number from the first enclosure")
    func bothVersions() {
        let data = appcast("""
        <item><enclosure url="https://example.invalid/a.zip" sparkle:version="1250" sparkle:shortVersionString="2.1"/></item>
        <item><enclosure url="https://example.invalid/b.zip" sparkle:version="1100" sparkle:shortVersionString="2.0"/></item>
        """)
        let release = SparkleAppcastChecker.parseLatestRelease(from: data)
        #expect(release == AppcastRelease(shortVersion: "2.1", buildVersion: "1250"))
    }

    @Test("a build-only enclosure carries no marketing version")
    func buildOnly() {
        let data = appcast(#"<item><enclosure url="https://example.invalid/a.zip" sparkle:version="1250"/></item>"#)
        #expect(SparkleAppcastChecker.parseLatestRelease(from: data) == AppcastRelease(buildVersion: "1250"))
    }

    @Test("a marketing-only enclosure carries no build number")
    func shortOnly() {
        let data = appcast(#"<item><enclosure url="https://example.invalid/a.zip" sparkle:shortVersionString="2.1"/></item>"#)
        #expect(SparkleAppcastChecker.parseLatestRelease(from: data) == AppcastRelease(shortVersion: "2.1"))
    }

    @Test("enclosures without a version are skipped; a feed with none yields nil")
    func skipsUnversionedEnclosures() {
        let skipped = appcast("""
        <item><enclosure url="https://example.invalid/none.zip"/></item>
        <item><enclosure url="https://example.invalid/a.zip" sparkle:shortVersionString="3.0"/></item>
        """)
        #expect(SparkleAppcastChecker.parseLatestRelease(from: skipped) == AppcastRelease(shortVersion: "3.0"))
        let none = appcast(#"<item><enclosure url="https://example.invalid/none.zip"/></item>"#)
        #expect(SparkleAppcastChecker.parseLatestRelease(from: none) == nil)
        #expect(SparkleAppcastChecker.parseLatestRelease(from: Data("not xml".utf8)) == nil)
    }

    @Test("the comparable pair: marketing against marketing, build against build, else nothing")
    func comparablePair() {
        // Marketing version present on both sides wins, even when the feed also has a build.
        let both = AppcastRelease(shortVersion: "2.1", buildVersion: "1250")
        #expect(both.verdict(installedVersion: "2.0", installedBuild: "1100")
                == AppcastVerdict(latestVersion: "2.1", installedBasis: "2.0"))
        // Build-only feed compares against the installed build.
        let buildOnly = AppcastRelease(buildVersion: "1250")
        #expect(buildOnly.verdict(installedVersion: "2.0", installedBuild: "1249")
                == AppcastVerdict(latestVersion: "1250", installedBasis: "1249"))
        // Build-only feed, installed app has no build: incomplete → nil (fail closed).
        #expect(buildOnly.verdict(installedVersion: "2.0", installedBuild: nil) == nil)
        // Marketing-only feed, installed app has no marketing version: incomplete → nil.
        #expect(AppcastRelease(shortVersion: "2.1").verdict(installedVersion: nil, installedBuild: "1249") == nil)
    }

    @Test("an InstalledAppsEnumerator reads the build number next to the marketing version")
    func enumeratorReadsBuildVersion() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("appversion-\(UUID().uuidString)")
        let contents = dir.appendingPathComponent("Alpha.app/Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let plist: [String: Any] = [
            "CFBundleIdentifier": "com.test.alpha",
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "42",
            "SUFeedURL": "https://updates.example.invalid/alpha/appcast.xml",
        ]
        (plist as NSDictionary).write(to: contents.appendingPathComponent("Info.plist"), atomically: true)
        let apps = InstalledAppsEnumerator(searchDirectories: [dir.path]).enumerate()
        #expect(apps.count == 1)
        #expect(apps.first?.version == "1.0")
        #expect(apps.first?.buildVersion == "42")
    }
}
