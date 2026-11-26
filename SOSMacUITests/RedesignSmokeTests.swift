import XCTest

/// Smoke test for the redesigned shell: every sidebar row exists and opens its screen.
///
/// It never captures the display. Screenshots are taken of the app's own window
/// element (`XCUIElement.screenshot()`), never `XCUIScreen.main`, so other apps and the
/// user's desktop cannot end up in an artifact.
///
/// XCUITest activates the app under test, so run this only with the owner's go-ahead.
/// For background captures use `Scripts/ui-snapshots.sh` instead.
///
/// Screen roots expose `<module>.state.<state>` accessibility identifiers once the
/// lifecycle frame lands (PR 4b); until a screen adopts it the test only requires its
/// sidebar row to exist and be clickable, and checks the state identifier when present.
final class RedesignSmokeTests: XCTestCase {
    private struct Destination {
        let label: String
        /// Prefix of the screen root's identifier, e.g. `junk` for `junk.state.idle`.
        let screenKey: String
    }

    /// Sidebar order (spec §3.2): ungrouped, Clean, Manage, Speed, Protect.
    private static let destinations: [Destination] = [
        Destination(label: "Dashboard", screenKey: "dashboard"),
        Destination(label: "Smart Care", screenKey: "smartcare"),
        Destination(label: "Junk & Cache", screenKey: "junk"),
        Destination(label: "Duplicate Finder", screenKey: "duplicates"),
        Destination(label: "Space Lens", screenKey: "spacelens"),
        Destination(label: "Cloud Cleanup", screenKey: "cloud"),
        Destination(label: "Uninstaller", screenKey: "uninstaller"),
        Destination(label: "Updater", screenKey: "updater"),
        Destination(label: "Performance", screenKey: "performance"),
        Destination(label: "Protection", screenKey: "protection"),
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testEverySidebarRowOpensItsScreen() throws {
        let app = XCUIApplication()
        app.launchEnvironment["SOSMAC_UITEST_APPEARANCE"] = "dark"
        app.launchEnvironment["SOSMAC_UITEST_FIXTURES"] = "1"
        app.launchEnvironment["SOSMAC_UITEST_WINDOW_SIZE"] = "1200x760"
        app.launch()
        defer { app.terminate() }

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10), "The app window did not appear")

        for destination in Self.destinations {
            let row = app.buttons["sidebar-nav-\(destination.label)"]
            XCTAssertTrue(row.waitForExistence(timeout: 10), "Missing sidebar row for \(destination.label)")
            // Spec §3.2: all ten rows fit without scrolling at the default 760 pt height.
            XCTAssertTrue(row.isHittable, "Sidebar row \(destination.label) is not visible at 1200x760")
            row.click()

            // Spec §3.3: the screen name is drawn once, by the toolbar's principal item.
            let title = app.descendants(matching: .any)["toolbar-title"]
            XCTAssertTrue(title.waitForExistence(timeout: 5), "Missing toolbar title for \(destination.label)")

            // Once a screen adopts the lifecycle frame its root carries `<key>.state.<state>`.
            let stateRoot = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH %@", "\(destination.screenKey).state."))
                .firstMatch
            if stateRoot.waitForExistence(timeout: 2) {
                XCTAssertTrue(stateRoot.exists)
            }

            // Element screenshot of the window only — never XCUIScreen.main.
            let attachment = XCTAttachment(screenshot: window.screenshot())
            attachment.name = "dark-\(destination.screenKey)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
