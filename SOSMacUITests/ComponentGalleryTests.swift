import XCTest

/// The Debug-only component gallery (`SOSMAC_UITEST_SCREEN=gallery`, `ComponentGalleryView`)
/// opens and lists every design-system primitive in every state.
///
/// It never captures the display: the attachment is the app's own window element
/// (`XCUIElement.screenshot()`), never `XCUIScreen.main`.
///
/// XCUITest activates the app under test, so run this only with the owner's go-ahead (OD-17).
/// For a background capture use `Scripts/ui-snapshots.sh -s gallery=default` instead.
final class ComponentGalleryTests: XCTestCase {
    /// `gallery.section.<key>` for every section of `ComponentGalleryView`.
    private static let sections = ["tiles", "buttons", "badges", "checkboxes", "steps", "banners", "results"]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testGalleryListsEverySection() throws {
        let app = XCUIApplication()
        app.launchEnvironment["SOSMAC_UITEST_SCREEN"] = "gallery"
        app.launchEnvironment["SOSMAC_UITEST_APPEARANCE"] = "dark"
        app.launchEnvironment["SOSMAC_UITEST_WINDOW_SIZE"] = "1200x1900"
        app.launch()
        defer { app.terminate() }

        let gallery = app.otherElements["gallery"]
        XCTAssertTrue(gallery.waitForExistence(timeout: 10), "The component gallery did not open")

        for key in Self.sections {
            let section = app.otherElements["gallery.section.\(key)"]
            XCTAssertTrue(section.exists, "Missing gallery section \"\(key)\"")
        }

        // Element screenshot of the window only — never XCUIScreen.main.
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = "gallery-dark"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
