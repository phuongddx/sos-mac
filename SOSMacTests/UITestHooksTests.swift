#if DEBUG
import Testing
import CoreGraphics
@testable import SOSMac

@Suite("UITestHooks")
struct UITestHooksTests {
    @Test func emptyEnvironmentMeansNormalBehaviour() {
        let hooks = UITestHooks(environment: [:])
        #expect(hooks.screen == nil)
        #expect(hooks.state == nil)
        #expect(hooks.appearance == nil)
        #expect(hooks.colorScheme == nil)
        #expect(hooks.fixtures == false)
        #expect(hooks.windowSize == nil)
        #expect(hooks.reduceTransparency == false)
        #expect(hooks.outputDirectory == nil)
        #expect(hooks.destination == nil)
    }

    @Test func readsEveryVariable() {
        let hooks = UITestHooks(environment: [
            "SOSMAC_UITEST_SCREEN": "junk",
            "SOSMAC_UITEST_STATE": "results",
            "SOSMAC_UITEST_APPEARANCE": "dark",
            "SOSMAC_UITEST_FIXTURES": "1",
            "SOSMAC_UITEST_WINDOW_SIZE": "1200x760",
            "SOSMAC_UITEST_REDUCE_TRANSPARENCY": "1",
            "SOSMAC_UITEST_OUTPUT_DIR": "/tmp/out",
        ])
        #expect(hooks.screen == "junk")
        #expect(hooks.state == "results")
        #expect(hooks.appearance == "dark")
        #expect(hooks.fixtures)
        #expect(hooks.windowSize == CGSize(width: 1200, height: 760))
        #expect(hooks.reduceTransparency)
        #expect(hooks.outputDirectory == "/tmp/out")
        #expect(hooks.destination == .junkCleaner)
    }

    @Test func ignoresUnprefixedAndInvalidValues() {
        let hooks = UITestHooks(environment: [
            "SCREEN": "junk",
            "SOSMAC_UITEST_APPEARANCE": "sepia",
            "SOSMAC_UITEST_SCREEN": "nope",
            "SOSMAC_UITEST_WINDOW_SIZE": "wide",
        ])
        #expect(hooks.appearance == nil)
        #expect(hooks.windowSize == nil)
        #expect(hooks.destination == nil)
    }

    @Test func parsesWindowSizeStrictly() {
        #expect(UITestHooks.parseSize("1200x760") == CGSize(width: 1200, height: 760))
        #expect(UITestHooks.parseSize("1200X760") == CGSize(width: 1200, height: 760))
        #expect(UITestHooks.parseSize("0x760") == nil)
        #expect(UITestHooks.parseSize("-1x5") == nil)
        #expect(UITestHooks.parseSize("1200") == nil)
        #expect(UITestHooks.parseSize("1x2x3") == nil)
        #expect(UITestHooks.parseSize(nil) == nil)
    }

    @Test func everyPrototypeScreenKeyMapsToADistinctDestination() {
        let keys = ["dashboard", "smartcare", "junk", "duplicates", "spacelens",
                    "cloud", "uninstaller", "updater", "performance", "protection"]
        let destinations = keys.compactMap(SidebarDestination.init(uiTestKey:))
        #expect(destinations.count == keys.count)
        #expect(Set(destinations).count == SidebarDestination.allCases.count)
    }
}

@Suite("UITestFixtures")
struct UITestFixturesTests {
    @Test func countsMatchThePlan() {
        #expect(UITestFixtures.junkRules.count == 4)
        #expect(UITestFixtures.duplicateSets.count == 6)
        #expect(UITestFixtures.similarSets.count == 2)
        #expect(UITestFixtures.apps.count == 10)
        #expect(UITestFixtures.updaterRows.count == 8)
        #expect(!UITestFixtures.findings.isEmpty)
        #expect(!UITestFixtures.quarantine.isEmpty)
        #expect(!UITestFixtures.spaceLensRoot.children.isEmpty)
    }

    @Test func duplicateSetsListNewestFirstAndHaveAtLeastTwoCopies() {
        for set in UITestFixtures.duplicateSets {
            #expect(set.items.count >= 2)
            let times = set.items.compactMap(\.lastModified)
            #expect(times == times.sorted(by: >), "\(set.title) must list the newest copy (the keep) first")
        }
    }

    @Test func helperRuleItemsRequireTheHelper() {
        for rule in UITestFixtures.junkRules {
            #expect(rule.items.allSatisfy { $0.requiresPrivilegedHelper == rule.requiresHelper })
        }
    }

    @Test func fixturesNeverPointAtARealUserHome() {
        let paths = UITestFixtures.junkRules.flatMap(\.items).map(\.path)
            + UITestFixtures.duplicateSets.flatMap(\.items).map(\.path)
            + UITestFixtures.similarSets.flatMap(\.items).map(\.path)
            + UITestFixtures.findings.map(\.path)
            + UITestFixtures.quarantine.map(\.originalPath)
        for path in paths {
            #expect(path.hasPrefix("/Users/sample/") || path.hasPrefix("/Library/Caches/"), "\(path)")
        }
    }
}
#endif
