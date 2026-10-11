import XCTest

/// iPad only: walks the main screens in landscape and portrait, so the regular-width layouts get exercised (and
/// leave screenshots in the result bundle). The simulator can't be rotated from the command line; XCUIDevice can.
final class IPadLayoutUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad layouts only")
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
    }

    func testMainScreensInBothOrientations() {
        let screens: [(name: String, args: [String])] = [
            ("dashboard", []),
            ("detail", ["-open-detail", "claude"]),
            ("costs", ["-open-costs"]),
            ("settings", ["-open-settings"]),
            ("more-providers", ["-open-settings", "-open-more-providers"]),
        ]
        for orientation in [UIDeviceOrientation.landscapeLeft, .portrait] {
            for screen in screens {
                let app = XCUIApplication()
                app.launchArguments = ["-demo"] + screen.args
                app.launch()
                XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
                // Rotating after launch, not before, gives the screenshot the settled landscape frame.
                XCUIDevice.shared.orientation = orientation
                sleep(3)
                let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                shot.name = "\(orientation == .portrait ? "portrait" : "landscape")-\(screen.name)"
                shot.lifetime = .keepAlways
                add(shot)
                app.terminate()
            }
        }
    }

    /// Settings navigation still works with the form sheet in landscape.
    func testMoreProvidersOpensInLandscape() {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-open-settings", "-open-more-providers"]
        app.launch()
        let row = app.collectionViews.staticTexts["DeepSeek"]   // the dashboard behind the sheet names it too
        XCTAssertTrue(row.waitForExistence(timeout: 10), "More providers list did not open")
        row.tap()
        XCTAssertTrue(app.navigationBars["DeepSeek"].waitForExistence(timeout: 5), "DeepSeek screen did not open")
    }
}
