import XCTest

/// Taps through Settings the way a person does, so navigation regressions (taps that go nowhere) are caught.
final class SettingsNavigationUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testFirstRunCardExplainsBothRelayOptions() {
        let app = XCUIApplication()
        app.launchArguments = ["-show-relay-setup", "-AppleLanguages", "(en)"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Connect your computer"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Windows or Linux")).firstMatch.exists)
        XCTAssertTrue(app.buttons["Choose relay file…"].exists)
    }

    func testSettingsShowsComputerRelayInstructions() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-open-settings", "-settings-scroll-relay", "-AppleLanguages", "(en)"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Your computer"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "iCloud Drive or OneDrive")).firstMatch.exists)
        XCTAssertTrue(app.buttons["Choose relay file…"].exists)
    }

    func testEachAPIKeyProviderOpensItsOwnScreen() {
        for name in ["GitHub Copilot", "OpenRouter", "DeepSeek", "Moonshot (Kimi)", "xAI"] {
            let app = XCUIApplication()
            app.launchArguments = ["-demo", "-open-settings", "-open-more-providers"]
            app.launch()
            // Scoped to the More providers form: on iPad the Settings form sheet leaves the dashboard (which also
            // names these providers) in the accessibility tree.
            let row = app.collectionViews.staticTexts[name]
            XCTAssertTrue(row.waitForExistence(timeout: 10), "\(name) row missing")
            row.tap()
            XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 5),
                          "Tapping \(name) did not open its key screen")
            XCTAssertTrue(app.secureTextFields.firstMatch.waitForExistence(timeout: 5),
                          "\(name) screen has no key field")
            app.terminate()
        }
    }

    func testMoreProvidersRowOpensTheList() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-open-settings"]
        app.launch()
        let link = app.buttons.containing(.staticText, identifier: "More providers").firstMatch
        let spanish = app.buttons.containing(.staticText, identifier: "Más proveedores").firstMatch
        let target = link.waitForExistence(timeout: 5) ? link : spanish
        for _ in 0..<6 where !target.isHittable { app.swipeUp() }
        target.tap()
        XCTAssertTrue(app.collectionViews.staticTexts["DeepSeek"].waitForExistence(timeout: 5), "More providers list did not open")
    }
}
