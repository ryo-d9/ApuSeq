import AppKit
import XCTest

final class ApuSeqUITests: XCTestCase {
    private var app: XCUIApplication!
    private var temporaryFiles: [URL] = []

    @MainActor
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    @MainActor
    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
        for url in temporaryFiles {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryFiles.removeAll()
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
    func testOpensSampleFASTAAndShowsAlignmentSummary() throws {
        launchApp(openingSampleFile: "demo.fasta")

        XCTAssertTrue(app.windows["demo.fasta"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["alignment-sequence-count"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["alignment-site-count"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testOpensSampleCLUSTALAndShowsAlignmentSummary() throws {
        launchApp(openingSampleFile: "demo.clustal")

        XCTAssertTrue(app.windows["demo.clustal"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["alignment-sequence-count"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["alignment-site-count"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testEditModeWarningAppearsForOpenedSample() throws {
        launchApp(openingSampleFile: "demo.fasta")
        XCTAssertTrue(app.windows["demo.fasta"].waitForExistence(timeout: 5))

        app.typeKey("e", modifierFlags: [.command, .option])

        let dialog = app.dialogs.firstMatch
        XCTAssertTrue(dialog.staticTexts["Changes in Edit mode are autosaved with versions."].waitForExistence(timeout: 5))
        XCTAssertTrue(dialog.buttons["Cancel"].waitForExistence(timeout: 2))
        dialog.buttons["Cancel"].click()
    }

    @MainActor
    func testOpenedNucleotideSampleEnablesAlignmentCommands() throws {
        launchApp(openingSampleFile: "demo.fasta")
        XCTAssertTrue(app.windows["demo.fasta"].waitForExistence(timeout: 5))

        openMenu("Alignment")

        XCTAssertTrue(app.menuItems["Reverse Complement"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.menuItems["Reverse Complement"].isEnabled)
        XCTAssertTrue(app.menuItems["Translation"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.menuItems["Translation"].isEnabled)

        dismissMenu()
    }

    @MainActor
    func testInspectorShowsOpenedFileInformation() throws {
        launchApp(openingSampleFile: "demo.fasta")
        XCTAssertTrue(app.windows["demo.fasta"].waitForExistence(timeout: 5))

        let inspectorButton = app.buttons["alignment-inspector-button"]
        XCTAssertTrue(inspectorButton.waitForExistence(timeout: 5))
        inspectorButton.click()

        XCTAssertTrue(app.staticTexts["Format"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["FASTA"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Sequence Kind"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Sequences"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Sites"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Selection"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Reference Sequence"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testCopyConsensusPlacesSequenceOnPasteboard() throws {
        launchApp(openingSampleFile: "demo.fasta")
        XCTAssertTrue(app.windows["demo.fasta"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["alignment-site-count"].waitForExistence(timeout: 5))

        NSPasteboard.general.clearContents()
        openMenu("Edit")
        let copyConsensus = app.menuItems["Copy Consensus"]
        XCTAssertTrue(copyConsensus.waitForExistence(timeout: 2))
        XCTAssertTrue(copyConsensus.isEnabled)
        copyConsensus.click()

        let copied = try XCTUnwrap(NSPasteboard.general.string(forType: .string))
        XCTAssertEqual(copied.count, 24)
        XCTAssertTrue(copied.hasPrefix("ATG"))
    }

    @MainActor
    func testEnteringEditModeEnablesSampleEditingCommands() throws {
        launchApp(openingSampleFile: "demo.fasta")
        XCTAssertTrue(app.windows["demo.fasta"].waitForExistence(timeout: 5))

        enterEditMode()
        openMenu("Edit")

        XCTAssertTrue(app.menuItems["Add Sequence..."].waitForExistence(timeout: 2))
        XCTAssertTrue(app.menuItems["Add Sequence..."].isEnabled)
        XCTAssertTrue(app.menuItems["Insert Gap Column"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.menuItems["Insert Gap Column"].isEnabled)

        dismissMenu()
    }

    @MainActor
    func testNewDocumentEnablesInitialSequenceCreationCommands() throws {
        launchApp()
        app.typeKey("n", modifierFlags: [.command])
        XCTAssertTrue(app.windows["Untitled"].waitForExistence(timeout: 5))

        enterEditMode()
        openMenu("Edit")

        XCTAssertTrue(app.menuItems["Add Sequence..."].waitForExistence(timeout: 2))
        XCTAssertTrue(app.menuItems["Add Sequence..."].isEnabled)
        XCTAssertTrue(app.menuItems["Add FASTA from Clipboard"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.menuItems["Add FASTA from Clipboard"].isEnabled)

        dismissMenu()
    }

    @MainActor
    func testNewDocumentAddFASTAFromClipboardCreatesEditableFASTAAlignment() throws {
        launchApp()
        app.typeKey("n", modifierFlags: [.command])
        XCTAssertTrue(app.windows["Untitled"].waitForExistence(timeout: 5))

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            """
            >Alpha
            ACGT
            >Beta
            A-GT
            """,
            forType: .string
        )

        enterEditMode()
        app.typeKey("v", modifierFlags: [.command, .shift])

        waitForStaticText("alignment-sequence-count", containing: "2")
        waitForStaticText("alignment-site-count", containing: "4")

        openMenu("Edit")
        XCTAssertTrue(app.menuItems["Add Sequence..."].waitForExistence(timeout: 2))
        XCTAssertTrue(app.menuItems["Add Sequence..."].isEnabled)
        XCTAssertTrue(app.menuItems["Add FASTA from Clipboard"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.menuItems["Add FASTA from Clipboard"].isEnabled)

        dismissMenu()
    }

    @MainActor
    func testAddSequenceUpdatesFooterCount() throws {
        let fileURL = try makeTemporaryAlignmentFile(
            name: "add-sequence-ui.fasta",
            contents: """
            >Alpha
            ACGT
            >Beta
            A-GT
            """
        )
        launchAppAndOpenDocument(fileURL)
        XCTAssertTrue(app.windows[fileURL.lastPathComponent].waitForExistence(timeout: 5))
        waitForStaticText("alignment-sequence-count", containing: "2")

        enterEditMode()
        app.typeKey("n", modifierFlags: [.command, .shift])

        let dialog = app.dialogs.firstMatch
        XCTAssertTrue(dialog.staticTexts["Add Sequence"].waitForExistence(timeout: 5))
        let nameField = dialog.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))
        nameField.click()
        nameField.typeKey("a", modifierFlags: [.command])
        nameField.typeText("UITest_added")
        dialog.buttons["OK"].click()

        waitForStaticText("alignment-sequence-count", containing: "3")
        waitForStaticText("alignment-site-count", containing: "4")
    }

    @MainActor
    func testAddFASTAFromClipboardUpdatesFooterCount() throws {
        let fileURL = try makeTemporaryAlignmentFile(
            name: "clipboard-ui.fasta",
            contents: """
            >Alpha
            ACGT
            >Beta
            A-GT
            """
        )
        launchAppAndOpenDocument(fileURL)
        XCTAssertTrue(app.windows[fileURL.lastPathComponent].waitForExistence(timeout: 5))
        waitForStaticText("alignment-sequence-count", containing: "2")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(">Gamma\nAC-T\n", forType: .string)
        enterEditMode()
        app.typeKey("v", modifierFlags: [.command, .shift])

        waitForStaticText("alignment-sequence-count", containing: "3")
        waitForStaticText("alignment-site-count", containing: "4")
    }

    @MainActor
    func testRemoveAllGapColumnsUpdatesFooterSiteCount() throws {
        let fileURL = try makeTemporaryAlignmentFile(
            name: "gap-columns-ui.fasta",
            contents: """
            >Alpha
            A--C
            >Beta
            T--G
            """
        )
        launchApp(opening: fileURL)
        XCTAssertTrue(app.windows[fileURL.lastPathComponent].waitForExistence(timeout: 5))
        waitForStaticText("alignment-site-count", containing: "4")

        enterEditMode()
        openMenu("Alignment")
        let removeAllGapColumns = app.menuItems["Remove All-Gap Columns"]
        XCTAssertTrue(removeAllGapColumns.waitForExistence(timeout: 2))
        XCTAssertTrue(removeAllGapColumns.isEnabled)
        removeAllGapColumns.click()

        waitForStaticText("alignment-site-count", containing: "2")
    }

    @MainActor
    func testUndoRedoRestoresSequenceTextEditingCounts() throws {
        let fileURL = try makeTemporaryAlignmentFile(
            name: "undo-redo-ui.fasta",
            contents: """
            >Alpha
            ACGT
            >Beta
            A-GT
            """
        )
        launchAppAndOpenDocument(fileURL)
        XCTAssertTrue(app.windows[fileURL.lastPathComponent].waitForExistence(timeout: 5))
        waitForStaticText("alignment-site-count", containing: "4")

        enterEditMode()
        insertResidueIntoSequenceText("A")
        waitForStaticText("alignment-site-count", containing: "5")

        clickFirstMenuItem(in: "Edit", titled: "Undo Edit", "Undo")
        waitForStaticText("alignment-site-count", containing: "4")

        clickFirstMenuItem(in: "Edit", titled: "Redo Edit", "Redo")
        waitForStaticText("alignment-site-count", containing: "5")
    }

    @MainActor
    func testEditingSequenceTextUpdatesAlignmentView() throws {
        let fileURL = try makeTemporaryAlignmentFile(
            name: "sequence-edit-ui.fasta",
            contents: """
            >Alpha
            ACGT
            >Beta
            A-GT
            """
        )
        launchApp(opening: fileURL)
        XCTAssertTrue(app.windows[fileURL.lastPathComponent].waitForExistence(timeout: 5))
        waitForStaticText("alignment-site-count", containing: "4")

        enterEditMode()
        insertResidueIntoSequenceText("A")

        waitForStaticText("alignment-site-count", containing: "5")
    }

    @MainActor
    func testSavesEditedDocumentAndReopensChangedAlignment() throws {
        let fileURL = try makeTemporaryAlignmentFile(
            name: "save-reopen-ui.fasta",
            contents: """
            >Alpha
            ACGT
            >Beta
            A-GT
            """
        )
        launchAppAndOpenDocument(fileURL)
        XCTAssertTrue(app.windows[fileURL.lastPathComponent].waitForExistence(timeout: 5))
        waitForStaticText("alignment-site-count", containing: "4")

        enterEditMode()
        insertResidueIntoSequenceText("A")
        waitForStaticText("alignment-site-count", containing: "5")
        saveDocument()
        waitForSavedAlignmentLength(fileURL, expectedLength: 5)

        relaunchApp(opening: fileURL)
        XCTAssertTrue(app.windows[fileURL.lastPathComponent].waitForExistence(timeout: 5))
        waitForStaticText("alignment-sequence-count", containing: "2")
        waitForStaticText("alignment-site-count", containing: "5")
    }

    @MainActor
    private func launchApp() {
        if !app.launchArguments.contains("-ApplePersistenceIgnoreState") {
            app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"] + app.launchArguments
        }
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    }

    @MainActor
    private func launchApp(openingSampleFile fileName: String) {
        app.launchArguments = [sampleFileURL(fileName).path]
        launchApp()
    }

    @MainActor
    private func launchApp(opening fileURL: URL) {
        app.launchArguments = [fileURL.path]
        launchApp()
    }

    @MainActor
    private func launchAppAndOpenDocument(_ fileURL: URL) {
        launchApp()
        openMenu("File")
        let openItem = app.menuItems["Open..."].exists ? app.menuItems["Open..."] : app.menuItems["Open…"]
        XCTAssertTrue(openItem.waitForExistence(timeout: 2))
        openItem.click()
        XCTAssertTrue(app.windows["Open"].waitForExistence(timeout: 5) || app.sheets.firstMatch.waitForExistence(timeout: 1))

        app.typeKey("g", modifierFlags: [.command, .shift])
        let pathField = app.comboBoxes.firstMatch.exists ? app.comboBoxes.firstMatch : app.textFields.firstMatch
        XCTAssertTrue(pathField.waitForExistence(timeout: 5))
        pathField.typeText(fileURL.path)
        app.typeKey(.return, modifierFlags: [])

        let openButton = app.windows["Open"].buttons["OKButton"]
        XCTAssertTrue(openButton.waitForExistence(timeout: 5))
        openButton.click()
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
    private func enterEditMode() {
        app.typeKey("e", modifierFlags: [.command, .option])

        let dialog = app.dialogs.firstMatch
        if dialog.waitForExistence(timeout: 2) {
            let enterButton = dialog.buttons["Enter Edit Mode"]
            XCTAssertTrue(enterButton.waitForExistence(timeout: 2))
            enterButton.click()
        }
    }

    @MainActor
    private func removeAllGapColumns() {
        openMenu("Alignment")
        let removeAllGapColumns = app.menuItems["Remove All-Gap Columns"]
        XCTAssertTrue(removeAllGapColumns.waitForExistence(timeout: 2))
        XCTAssertTrue(removeAllGapColumns.isEnabled)
        removeAllGapColumns.click()
    }

    @MainActor
    private func clickFirstMenuItem(in menuTitle: String, titled titles: String...) {
        openMenu(menuTitle)
        for title in titles {
            let item = app.menuItems[title]
            if item.waitForExistence(timeout: 1), item.isEnabled {
                item.click()
                return
            }
        }
        XCTFail("No enabled menu item found in \(menuTitle): \(titles.joined(separator: ", "))")
    }

    @MainActor
    private func insertResidueIntoSequenceText(_ residue: String) {
        let sequenceTextView = app.descendants(matching: .textView)["alignment-sequence-text"]
        XCTAssertTrue(sequenceTextView.waitForExistence(timeout: 5))
        sequenceTextView.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.08)).click()
        app.typeText(residue)
    }

    @MainActor
    private func saveDocument() {
        app.typeKey("s", modifierFlags: [.command])
    }

    @MainActor
    private func relaunchApp(opening fileURL: URL) {
        app.terminate()
        app = XCUIApplication()
        launchApp(opening: fileURL)
    }

    private func sampleFileURL(_ fileName: String) -> URL {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let repositoryRootURL = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return repositoryRootURL
            .appendingPathComponent("SampleData")
            .appendingPathComponent(fileName)
    }

    private func makeTemporaryAlignmentFile(name: String, contents: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ApuSeqUITests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent(name)
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        temporaryFiles.append(directory)
        return fileURL
    }

    @MainActor
    private func dismissMenu() {
        app.typeKey(.escape, modifierFlags: [])
    }

    @MainActor
    private func waitForStaticText(
        _ identifier: String,
        containing expectedText: String,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let element = app.staticTexts[identifier]
        XCTAssertTrue(element.waitForExistence(timeout: timeout), file: file, line: line)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let value = element.value as? String
            if element.label.contains(expectedText) || value?.contains(expectedText) == true {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTFail(
            "Expected \(identifier) to contain \(expectedText), label: \(element.label), value: \(String(describing: element.value))",
            file: file,
            line: line
        )
    }

    private func waitForSavedAlignmentLength(
        _ fileURL: URL,
        expectedLength: Int,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let contents = try? String(contentsOf: fileURL, encoding: .utf8),
               fastaSequenceLengths(in: contents).contains(expectedLength) {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        let contents = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? "<unreadable>"
        XCTFail(
            "Expected \(fileURL.path) to contain a FASTA sequence of length \(expectedLength), contents: \(contents)",
            file: file,
            line: line
        )
    }

    private func fastaSequenceLengths(in contents: String) -> [Int] {
        var lengths: [Int] = []
        var currentLength = 0
        var hasCurrentSequence = false

        for line in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix(">") {
                if hasCurrentSequence {
                    lengths.append(currentLength)
                }
                currentLength = 0
                hasCurrentSequence = true
            } else if hasCurrentSequence {
                currentLength += line.trimmingCharacters(in: .whitespacesAndNewlines).count
            }
        }

        if hasCurrentSequence {
            lengths.append(currentLength)
        }
        return lengths
    }
}
