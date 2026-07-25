import XCTest

final class ApuSeqUITests: XCTestCase {
    private var app: XCUIApplication!

    @MainActor
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    @MainActor
    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    @MainActor
    func testLaunchesToForeground() throws {
        launchApp()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    }

    @MainActor
    func testFileMenuContainsDocumentCommands() throws {
        launchApp()

        openMenu("File")

        XCTAssertTrue(app.menuItems["New"].waitForExistence(timeout: 2))
        XCTAssertTrue(menuItemExists("Open...", "Open…"))
        XCTAssertTrue(menuItemExists("Save...", "Save…", "Save"))
        XCTAssertTrue(app.menuItems["Revert To"].waitForExistence(timeout: 2))

        dismissMenu()
    }

    @MainActor
    func testViewMenuContainsDisplayCommands() throws {
        launchApp()

        openMenu("View")

        XCTAssertTrue(app.menuItems["Background Color"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.menuItems["Display Order"].waitForExistence(timeout: 2))
        XCTAssertTrue(menuItemExists("Show Reference Panel", "Hide Reference Panel"))
        XCTAssertTrue(menuItemExists("Show Consensus Panel", "Hide Consensus Panel"))
        XCTAssertTrue(menuItemExists("Show Identity Panel", "Hide Identity Panel"))

        dismissMenu()
    }

    @MainActor
    func testEditMenuContainsSequenceEditingCommands() throws {
        launchApp()

        openMenu("Edit")

        XCTAssertTrue(app.menuItems["Copy Consensus"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.menuItems["Select"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.menuItems["Add Sequence..."].waitForExistence(timeout: 2))
        XCTAssertTrue(app.menuItems["Add FASTA from Clipboard"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.menuItems["Insert Gap Column"].waitForExistence(timeout: 2))

        dismissMenu()
    }

    @MainActor
    func testAlignmentMenuContainsAnalysisAndEditingCommands() throws {
        launchApp()

        openMenu("Alignment")

        XCTAssertTrue(app.menuItems["Align with MAFFT"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.menuItems["Remove All-Gap Columns"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.menuItems["Trim Trailing Gaps"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.menuItems["Sort Sequences"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.menuItems["Reverse Complement"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.menuItems["Translation"].waitForExistence(timeout: 2))

        dismissMenu()
    }

    @MainActor
    func testSettingsWindowShowsPrimaryPreferences() throws {
        launchApp()

        app.typeKey(",", modifierFlags: [.command])

        XCTAssertTrue(app.staticTexts["General"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Font Size"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Identity Threshold"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Translation"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testHelpMenuOpensOpenSourceLicensesWindow() throws {
        launchApp()

        openMenu("Help")
        let licensesItem = app.menuItems["Open Source Licenses..."]
        XCTAssertTrue(licensesItem.waitForExistence(timeout: 2))
        licensesItem.click()

        XCTAssertTrue(app.windows["Open Source Licenses"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["MAFFT"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Multiple sequence alignment program"].waitForExistence(timeout: 2))
    }

    @MainActor
    private func launchApp() {
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    }

    @MainActor
    private func openMenu(_ title: String) {
        let menu = app.menuBars.menuBarItems[title]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.click()
    }

    @MainActor
    private func menuItemExists(_ titles: String...) -> Bool {
        titles.contains { app.menuItems[$0].waitForExistence(timeout: 1) }
    }

    @MainActor
    private func dismissMenu() {
        app.typeKey(.escape, modifierFlags: [])
    }
}
