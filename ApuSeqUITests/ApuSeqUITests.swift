import XCTest

final class ApuSeqUITests: XCTestCase {
    @MainActor
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchesToForeground() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    }

    @MainActor
    func testViewMenuContainsDisplayCommands() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))

        let viewMenu = app.menuBars.menuBarItems["View"]
        XCTAssertTrue(viewMenu.waitForExistence(timeout: 5))
        viewMenu.click()

        XCTAssertTrue(app.menuItems["Background Color"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.menuItems["Sequence Order"].waitForExistence(timeout: 2))

        app.typeKey(.escape, modifierFlags: [])
    }
}
