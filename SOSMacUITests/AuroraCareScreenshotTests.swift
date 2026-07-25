import XCTest

/// Drives every real screen in both light and dark appearance and captures a
/// screenshot of each, so the Aurora Care re-skin (hue-coded sidebar/cards,
/// aurora bloom, hero panels) can be verified visually without depending on
/// — or mutating — the developer's actual system appearance. Appearance is
/// forced via the `SOSMAC_UITEST_APPEARANCE` launch environment variable,
/// which `RootView` only reads for this purpose; a normal launch never sets
/// it, so production behavior is unaffected.
final class AuroraCareScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Settings has no case in `SidebarDestination` yet, so it's excluded —
    /// there is no screen to screenshot.
    private static let destinations = [
        "Dashboard", "Smart Care", "Junk & Cache Scanner", "Uninstaller",
        "Updater", "Space Lens", "Duplicate Finder", "Performance",
        "Cloud Cleanup", "Protection",
    ]

    func testScreenshotAllScreensInBothAppearances() throws {
        let outputDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sosmac-aurora-care-screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        for appearance in ["light", "dark"] {
            let app = XCUIApplication()
            app.launchEnvironment["SOSMAC_UITEST_APPEARANCE"] = appearance
            app.launch()

            for destination in Self.destinations {
                let row = app.buttons["sidebar-nav-\(destination)"]
                XCTAssertTrue(row.waitForExistence(timeout: 10), "Missing sidebar row for \(destination)")
                row.click()

                // Let the detail view settle (view transition + any onAppear
                // work like polling snapshots) before capturing.
                Thread.sleep(forTimeInterval: 0.4)

                let screenshot = XCUIScreen.main.screenshot()
                let attachment = XCTAttachment(screenshot: screenshot)
                attachment.name = "\(appearance)-\(destination)"
                attachment.lifetime = .keepAlways
                add(attachment)

                let safeName = destination
                    .replacingOccurrences(of: " & ", with: "-")
                    .replacingOccurrences(of: " ", with: "-")
                let fileURL = outputDir.appendingPathComponent("\(appearance)-\(safeName).png")
                try screenshot.pngRepresentation.write(to: fileURL)
            }

            app.terminate()
        }
    }
}
