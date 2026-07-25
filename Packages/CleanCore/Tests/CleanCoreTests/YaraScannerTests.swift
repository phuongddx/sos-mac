import Foundation
import Testing
@testable import CleanCore

struct YaraScannerTests {
    private static let markerRule = """
    rule sos_mac_test_marker_detection {
        strings:
            $marker = "SOS_MAC_TEST_MARKER_7f3a9c"
        condition:
            $marker
    }
    """

    @Test func detectsAFileContainingTheRulesMarkerString() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let fixtureURL = root.appendingPathComponent("suspicious.bin")
        try Data("prefix bytes SOS_MAC_TEST_MARKER_7f3a9c trailing bytes".utf8).write(to: fixtureURL)

        let scanner = try YaraScanner(ruleSources: [Self.markerRule])
        let matches = try scanner.scan(filePath: fixtureURL.path)

        #expect(matches.count == 1)
        #expect(matches.first?.ruleIdentifier == "sos_mac_test_marker_detection")
    }

    @Test func doesNotFlagAFileWithoutTheMarker() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let fixtureURL = root.appendingPathComponent("clean.bin")
        try Data("nothing suspicious in here at all".utf8).write(to: fixtureURL)

        let scanner = try YaraScanner(ruleSources: [Self.markerRule])
        let matches = try scanner.scan(filePath: fixtureURL.path)

        #expect(matches.isEmpty)
    }

    @Test func multipleRulesCanMatchTheSameFileIndependently() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let secondRule = """
        rule sos_mac_second_marker {
            strings:
                $marker = "SECOND_MARKER_9b1e"
            condition:
                $marker
        }
        """

        let fixtureURL = root.appendingPathComponent("double.bin")
        try Data("SOS_MAC_TEST_MARKER_7f3a9c ... SECOND_MARKER_9b1e".utf8).write(to: fixtureURL)

        let scanner = try YaraScanner(ruleSources: [Self.markerRule, secondRule])
        let matches = try scanner.scan(filePath: fixtureURL.path)

        #expect(Set(matches.map(\.ruleIdentifier)) == Set(["sos_mac_test_marker_detection", "sos_mac_second_marker"]))
    }

    @Test func malformedRuleSourceThrowsRuleCompilationFailed() {
        let malformedRule = "this is not valid yara syntax {{{"

        #expect(throws: YaraScannerError.self) {
            _ = try YaraScanner(ruleSources: [malformedRule])
        }
    }
}
