import AppKit

final class AlignmentViewportSequenceTextView: NSTextView {
    private struct SelectionState {
        let selectedRanges: [NSValue]
        let columnSelectionRanges: [NSRange]
        let columnSelectionAnchor: Int?
        let columnSelectionWidth: Int
        let alignmentLength: Int
    }

    private struct TextPatch {
        let oldRange: NSRange
        let newRange: NSRange
        let oldText: String
        let newText: String
    }

    var onAddVerticalCursor: ((Int) -> Bool)?
    var onAddSequence: (() -> Void)?
    var canAddSequenceFromMenu = true
    var rowNames: [String] = []
    var columnSelectionAnchor: Int?
    var columnSelectionWidth: Int = 1
    var columnSelectionRanges: [NSRange] = []
    private var pendingEditedRanges: [NSRange] = []

    var alignmentLength = 0
    private var identityByColumn: [Double] = []
    private var majorityResidueByColumn: [UInt16] = []
    private var backgroundMode: AlignmentBackgroundMode = .residue
    private var referenceSequenceForBackground: String?
    private var referenceTextForBackground: NSString?
    private var identityColorThreshold = 0.5

    func replaceAlignmentText(_ text: String) {
        guard let textStorage else { return }
        let font = font ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textStorage.beginEditing()
        textStorage.replaceCharacters(
            in: NSRange(location: 0, length: textStorage.length),
            with: text
        )
        textStorage.setAttributes(
            [
                .font: font,
                .foregroundColor: NSColor.labelColor
            ],
            range: NSRange(location: 0, length: textStorage.length)
        )
        textStorage.endEditing()
    }

    func applyAlignmentReplacement(_ replacement: String, to ranges: [NSRange]) {
        guard textStorage != nil else { return }
        guard !ranges.isEmpty, alignmentLength > 0 else { return }
        guard AlignmentSequenceInput.isValidEditingReplacement(replacement) else {
            NSSound.beep()
            return
        }

        let previousSelection = captureSelectionState()
        let lines = sequenceLines()
        guard !lines.isEmpty else { return }
        let edits = normalizedEdits(from: ranges, rowCount: lines.count)
        guard !edits.isEmpty else { return }

        let replacementLength = (replacement as NSString).length
        let rowEdits = edits.map {
            AlignmentColumnEditor.RowEdit(
                row: $0.row,
                column: $0.column,
                length: $0.length,
                replacement: replacement
            )
        }
        guard let edited = AlignmentColumnEditor.replacingRowsOnly(in: lines, edits: rowEdits) else { return }

        let patches = textPatches(from: lines, to: edited.sequences)
        guard !patches.isEmpty else { return }
        apply(patches, direction: .forward)
        alignmentLength = edited.length
        let newSelections = edits.map { edit in
            let location = (edit.row * (edited.length + 1)) + min(edit.column + replacementLength, edited.length)
            return NSRange(location: location, length: 0)
        }
        setSelectedRanges(
            newSelections.map(NSValue.init(range:)),
            affinity: .downstream,
            stillSelecting: false
        )
        columnSelectionRanges = newSelections.count > 1 ? newSelections : []
        let nextSelection = captureSelectionState()
        registerPatchUndo(
            patches,
            restoreSelection: previousSelection,
            inverseSelection: nextSelection,
            actionName: String(localized: "Edit")
        )
        didChangeText()
    }

    private func captureSelectionState() -> SelectionState {
        SelectionState(
            selectedRanges: selectedRanges,
            columnSelectionRanges: columnSelectionRanges,
            columnSelectionAnchor: columnSelectionAnchor,
            columnSelectionWidth: columnSelectionWidth,
            alignmentLength: alignmentLength
        )
    }

    private func applySelectionState(_ state: SelectionState) {
        alignmentLength = state.alignmentLength
        setSelectedRanges(state.selectedRanges, affinity: .downstream, stillSelecting: false)
        columnSelectionRanges = state.columnSelectionRanges
        columnSelectionAnchor = state.columnSelectionAnchor
        columnSelectionWidth = state.columnSelectionWidth
    }

    private enum PatchDirection {
        case forward
        case reverse
    }

    private func apply(_ patches: [TextPatch], direction: PatchDirection) {
        guard let textStorage else { return }
        textStorage.beginEditing()
        for patch in patches.reversed() {
            switch direction {
            case .forward:
                textStorage.replaceCharacters(in: patch.oldRange, with: patch.newText)
            case .reverse:
                textStorage.replaceCharacters(in: patch.newRange, with: patch.oldText)
            }
        }
        textStorage.endEditing()
        switch direction {
        case .forward:
            pendingEditedRanges = patches.map(\.newRange)
        case .reverse:
            pendingEditedRanges = patches.map(\.oldRange)
        }
    }

    func consumeEditedRanges() -> [NSRange] {
        defer { pendingEditedRanges = [] }
        return pendingEditedRanges
    }

    private func registerPatchUndo(
        _ patches: [TextPatch],
        restoreSelection: SelectionState,
        inverseSelection: SelectionState,
        actionName: String
    ) {
        guard allowsUndo, let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { target in
            target.apply(patches, direction: .reverse)
            target.applySelectionState(restoreSelection)
            target.registerPatchRedo(
                patches,
                restoreSelection: inverseSelection,
                inverseSelection: restoreSelection,
                actionName: actionName
            )
            target.didChangeText()
        }
        undoManager.setActionName(actionName)
    }

    private func registerPatchRedo(
        _ patches: [TextPatch],
        restoreSelection: SelectionState,
        inverseSelection: SelectionState,
        actionName: String
    ) {
        guard allowsUndo, let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { target in
            target.apply(patches, direction: .forward)
            target.applySelectionState(restoreSelection)
            target.registerPatchUndo(
                patches,
                restoreSelection: inverseSelection,
                inverseSelection: restoreSelection,
                actionName: actionName
            )
            target.didChangeText()
        }
        undoManager.setActionName(actionName)
    }

    private func textPatches(from oldLines: [String], to newLines: [String]) -> [TextPatch] {
        guard oldLines.count == newLines.count else { return [] }
        var patches: [TextPatch] = []
        var oldLineStart = 0
        var newLineStart = 0

        for (oldLine, newLine) in zip(oldLines, newLines) {
            let oldText = oldLine as NSString
            let newText = newLine as NSString
            let commonPrefix = commonPrefixLength(oldText, newText)
            let commonSuffix = commonSuffixLength(oldText, newText, excludingPrefix: commonPrefix)
            let oldLength = oldText.length - commonPrefix - commonSuffix
            let newLength = newText.length - commonPrefix - commonSuffix

            if oldLength > 0 || newLength > 0 {
                patches.append(
                    TextPatch(
                        oldRange: NSRange(location: oldLineStart + commonPrefix, length: oldLength),
                        newRange: NSRange(location: newLineStart + commonPrefix, length: newLength),
                        oldText: oldText.substring(with: NSRange(location: commonPrefix, length: oldLength)),
                        newText: newText.substring(with: NSRange(location: commonPrefix, length: newLength))
                    )
                )
            }

            oldLineStart += oldText.length + 1
            newLineStart += newText.length + 1
        }
        return patches
    }

    private func commonPrefixLength(_ first: NSString, _ second: NSString) -> Int {
        let maximum = min(first.length, second.length)
        var length = 0
        while length < maximum, first.character(at: length) == second.character(at: length) {
            length += 1
        }
        return length
    }

    private func commonSuffixLength(_ first: NSString, _ second: NSString, excludingPrefix prefix: Int) -> Int {
        let maximum = min(first.length, second.length) - prefix
        var length = 0
        while length < maximum,
              first.character(at: first.length - length - 1) == second.character(at: second.length - length - 1) {
            length += 1
        }
        return length
    }

    private func normalizedEdits(from ranges: [NSRange], rowCount: Int) -> [AlignmentColumnEditor.RowEdit] {
        let lineSpan = alignmentLength + 1
        return ranges.compactMap { range in
            guard range.location >= 0 else { return nil }
            let row = range.location / lineSpan
            let column = range.location % lineSpan
            guard row >= 0, row < rowCount, column <= alignmentLength else { return nil }
            guard column < alignmentLength || range.length == 0 else { return nil }
            let length = min(max(range.length, 0), alignmentLength - column)
            return AlignmentColumnEditor.RowEdit(row: row, column: column, length: length, replacement: "")
        }
    }

    private func sequenceLines() -> [String] {
        var lines = string
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        if lines.last == "" {
            lines.removeLast()
        }
        return lines
    }

    private func currentSequenceLineLength() -> Int {
        sequenceLines().map { ($0 as NSString).length }.max() ?? 0
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        guard isEditable else {
            super.insertText(insertString, replacementRange: replacementRange)
            return
        }
        let ranges = columnSelectionRanges
        guard ranges.count > 1 else {
            super.insertText(insertString, replacementRange: replacementRange)
            return
        }

        let replacement: String
        if let attributed = insertString as? NSAttributedString {
            replacement = attributed.string
        } else if let string = insertString as? String {
            replacement = string
        } else {
            replacement = "\(insertString)"
        }

        applyAlignmentReplacement(replacement, to: ranges)
    }

    @objc func selectColumnUp(_ sender: Any?) {
        _ = onAddVerticalCursor?(-1)
    }

    @objc func selectColumnDown(_ sender: Any?) {
        _ = onAddVerticalCursor?(1)
    }

    @objc func insertGapColumn(_ sender: Any?) {
        guard isEditable else { return }
        guard textStorage != nil else { return }
        let lines = sequenceLines()
        guard !lines.isEmpty, alignmentLength > 0 else {
            NSSound.beep()
            return
        }

        let selection = selectedRange()
        let lineSpan = alignmentLength + 1
        let row = selection.location / lineSpan
        let column = selection.location % lineSpan
        guard row >= 0, row < lines.count, column <= alignmentLength else {
            NSSound.beep()
            return
        }

        let previousSelection = captureSelectionState()
        let rows = lines.enumerated().map { index, sequence in
            AlignmentRow(name: "Row \(index + 1)", sequence: sequence)
        }
        guard let editedRows = AlignmentColumnEditor.insertingGapColumn(in: rows, column: column) else {
            NSSound.beep()
            return
        }

        let editedSequences = editedRows.map(\.sequence)
        let patches = textPatches(from: lines, to: editedSequences)
        guard !patches.isEmpty else { return }
        apply(patches, direction: .forward)
        alignmentLength += 1
        let nextLocation = row * (alignmentLength + 1) + min(column + 1, alignmentLength)
        setSelectedRange(NSRange(location: nextLocation, length: 0))
        columnSelectionRanges = []
        columnSelectionAnchor = nil
        let nextSelection = captureSelectionState()
        registerPatchUndo(
            patches,
            restoreSelection: previousSelection,
            inverseSelection: nextSelection,
            actionName: AppStrings.insertGapColumn
        )
        didChangeText()
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isControlShift = flags.contains([.control, .shift]) && !flags.contains(.command) && !flags.contains(.option)
        if isControlShift {
            if event.keyCode == 126, onAddVerticalCursor?(-1) == true { return }
            if event.keyCode == 125, onAddVerticalCursor?(1) == true { return }
        }
        super.keyDown(with: event)
    }

    override func doCommand(by selector: Selector) {
        let flags = NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
        let isControlShift = flags.contains([.control, .shift]) && !flags.contains(.command) && !flags.contains(.option)
        if isControlShift {
            if selector == #selector(moveUp(_:)), onAddVerticalCursor?(-1) == true { return }
            if selector == #selector(moveDown(_:)), onAddVerticalCursor?(1) == true { return }
            if selector == #selector(moveUpAndModifySelection(_:)), onAddVerticalCursor?(-1) == true { return }
            if selector == #selector(moveDownAndModifySelection(_:)), onAddVerticalCursor?(1) == true { return }
        }
        super.doCommand(by: selector)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu(title: AppStrings.sequenceMenu)
        if canCopySelectionAsFASTA {
            if !menu.items.isEmpty {
                menu.addItem(.separator())
            }
            let copySelectionItem = NSMenuItem(title: AppStrings.copySelectionAsFASTA, action: #selector(copySelectionAsFASTA(_:)), keyEquivalent: "")
            copySelectionItem.target = self
            menu.addItem(copySelectionItem)
        }
        guard isEditable && canAddSequenceFromMenu else { return menu }
        if !menu.items.isEmpty {
            menu.addItem(.separator())
        }
        let addItem = NSMenuItem(title: AppStrings.addSequence, action: #selector(addSequenceFromMenu(_:)), keyEquivalent: "")
        addItem.target = self
        menu.addItem(addItem)
        return menu
    }

    @objc private func addSequenceFromMenu(_ sender: NSMenuItem) {
        onAddSequence?()
    }

    @objc func copySelectionAsFASTA(_ sender: Any?) {
        guard let fasta = AlignmentSelectionExporter.selectedFASTAString(
            text: string,
            rowNames: rowNames,
            alignmentLength: alignmentLength,
            selectedRanges: selectedRanges.map(\.rangeValue)
        ), !fasta.isEmpty else {
            NSSound.beep()
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(fasta, forType: .string)
    }

    private var canCopySelectionAsFASTA: Bool {
        selectedRanges.contains { $0.rangeValue.length > 0 } && alignmentLength > 0
    }

    func updateAlignmentDisplay(
        alignmentLength: Int,
        identityByColumn: [Double],
        majorityResidueByColumn: [UInt16],
        backgroundMode: AlignmentBackgroundMode,
        referenceSequenceForBackground: String?,
        identityColorThreshold: Double
    ) {
        let effectiveAlignmentLength = isEditable
            ? max(alignmentLength, currentSequenceLineLength())
            : alignmentLength
        let needsRedraw =
            self.alignmentLength != effectiveAlignmentLength ||
            self.identityByColumn.count != identityByColumn.count ||
            self.majorityResidueByColumn.count != majorityResidueByColumn.count ||
            self.backgroundMode != backgroundMode ||
            self.referenceSequenceForBackground != referenceSequenceForBackground ||
            abs(self.identityColorThreshold - identityColorThreshold) > 0.001
        self.alignmentLength = effectiveAlignmentLength
        self.identityByColumn = identityByColumn
        self.majorityResidueByColumn = majorityResidueByColumn
        self.backgroundMode = backgroundMode
        self.referenceSequenceForBackground = referenceSequenceForBackground
        self.referenceTextForBackground = referenceSequenceForBackground.map { $0 as NSString }
        self.identityColorThreshold = identityColorThreshold
        if needsRedraw {
            needsDisplay = true
        }
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard backgroundMode != .none else { return }
        guard alignmentLength > 0 else { return }
        guard let font else { return }

        let charWidth = max(("M" as NSString).size(withAttributes: [.font: font]).width, 1)
        let lineHeight = alignmentLineHeight(for: font)
        let inset = textContainerInset
        let lineSpan = alignmentLength + 1
        let text = string as NSString
        let textLength = text.length
        guard textLength > 0 else { return }

        let visibleMinY = max(rect.minY - inset.height, 0)
        let visibleMaxY = max(rect.maxY - inset.height, 0)
        let firstRow = max(Int(floor(visibleMinY / lineHeight)), 0)
        let lastRow = min(Int(ceil(visibleMaxY / lineHeight)), max(textLength / lineSpan, 0))
        let firstColumn = max(Int(floor((rect.minX - inset.width) / charWidth)), 0)
        let lastColumn = min(Int(ceil((rect.maxX - inset.width) / charWidth)), alignmentLength - 1)
        guard firstRow <= lastRow, firstColumn <= lastColumn else { return }

        for row in firstRow...lastRow {
            let rowStart = row * lineSpan
            guard rowStart < textLength else { continue }
            var runStart: Int?
            var runColor: NSColor?

            func flushRun(endColumn: Int) {
                guard let start = runStart, let color = runColor, endColumn > start else { return }
                color.setFill()
                let runRect = NSRect(
                    x: inset.width + CGFloat(start) * charWidth,
                    y: inset.height + CGFloat(row) * lineHeight,
                    width: CGFloat(endColumn - start) * charWidth,
                    height: lineHeight
                )
                runRect.fill()
            }

            for column in firstColumn...lastColumn {
                guard rowStart + column < textLength else { break }
                guard let color = backgroundColor(in: text, at: rowStart + column, column: column) else {
                    flushRun(endColumn: column)
                    runStart = nil
                    runColor = nil
                    continue
                }
                if runStart == nil {
                    runStart = column
                    runColor = color
                } else if color != runColor {
                    flushRun(endColumn: column)
                    runStart = column
                    runColor = color
                }
            }
            flushRun(endColumn: lastColumn + 1)
        }
    }

    private func backgroundColor(in text: NSString, at textIndex: Int, column: Int) -> NSColor? {
        switch backgroundMode {
        case .none:
            return nil
        case .residue:
            return ResiduePalette.backgroundColor(for: text.character(at: textIndex))
        case .minority:
            let residue = normalizedResidueCode(text.character(at: textIndex))
            guard let majorityResidue = majorityResidueByColumn[safe: column], majorityResidue != 0 else { return nil }
            guard residue != majorityResidue else { return nil }
            return ResiduePalette.backgroundColor(for: residue)
        case .reference:
            guard let referenceTextForBackground, column < referenceTextForBackground.length else { return nil }
            return ReferenceDifferencePalette.backgroundColor(
                for: text.character(at: textIndex),
                referenceResidue: referenceTextForBackground.character(at: column)
            )
        case .identity:
            return identityByColumn[safe: column].flatMap {
                IdentityPalette.backgroundColor(for: $0, threshold: identityColorThreshold)
            }
        }
    }
}
