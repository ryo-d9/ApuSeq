import AppKit

final class AlignmentViewportSequenceTextView: NSTextView {
    private struct ColumnEditState {
        let attributedText: NSAttributedString
        let selectedRanges: [NSValue]
        let columnSelectionRanges: [NSRange]
        let columnSelectionAnchor: Int?
        let columnSelectionWidth: Int
        let alignmentLength: Int
    }

    private struct AlignmentEdit {
        let row: Int
        let column: Int
        let length: Int
    }

    var onAddVerticalCursor: ((Int) -> Bool)?
    var onAddSequence: (() -> Void)?
    var columnSelectionAnchor: Int?
    var columnSelectionWidth: Int = 1
    var columnSelectionRanges: [NSRange] = []

    var alignmentLength = 0
    private var identityByColumn: [Double] = []
    private var majorityResidueByColumn: [UInt16] = []
    private var backgroundMode: AlignmentBackgroundMode = .residue
    private var identityColorThreshold = 0.5

    func applyAlignmentReplacement(_ replacement: String, to ranges: [NSRange]) {
        guard let textStorage else { return }
        guard !ranges.isEmpty, alignmentLength > 0 else { return }
        guard !replacement.contains("\n") else { return }

        let previousState = captureColumnEditState()
        var lines = sequenceLines()
        guard !lines.isEmpty else { return }
        let edits = normalizedEdits(from: ranges, rowCount: lines.count)
        guard !edits.isEmpty else { return }

        let replacementLength = (replacement as NSString).length
        var editGroups: [String: (column: Int, length: Int, rows: Set<Int>)] = [:]
        for edit in edits {
            let key = "\(edit.column):\(edit.length)"
            if editGroups[key] == nil {
                editGroups[key] = (edit.column, edit.length, [])
            }
            editGroups[key]?.rows.insert(edit.row)
        }

        var nextAlignmentLength = alignmentLength
        let groups = editGroups.values.sorted { lhs, rhs in
            if lhs.column == rhs.column { return lhs.length > rhs.length }
            return lhs.column > rhs.column
        }
        for group in groups {
            let extraColumns = max(replacementLength - group.length, 0)
            for row in lines.indices {
                if group.rows.contains(row) {
                    replaceCharacters(in: &lines[row], column: group.column, length: group.length, with: replacement)
                    if replacementLength < group.length {
                        lines[row] += String(repeating: "-", count: group.length - replacementLength)
                    }
                } else if extraColumns > 0 {
                    insertCharacters(String(repeating: "-", count: extraColumns), in: &lines[row], column: group.column + group.length)
                }
            }
            nextAlignmentLength += extraColumns
        }

        alignmentLength = nextAlignmentLength
        textStorage.setAttributedString(attributedSequenceText(from: lines))
        let newSelections = edits.map { edit in
            let location = (edit.row * (nextAlignmentLength + 1)) + min(edit.column + replacementLength, nextAlignmentLength)
            return NSRange(location: location, length: 0)
        }
        setSelectedRanges(
            newSelections.map(NSValue.init(range:)),
            affinity: .downstream,
            stillSelecting: false
        )
        columnSelectionRanges = newSelections
        registerColumnUndo(toRestore: previousState)
        didChangeText()
    }

    private func captureColumnEditState() -> ColumnEditState {
        let textSnapshot = textStorage?.copy() as? NSAttributedString ?? NSAttributedString(string: string)
        return ColumnEditState(
            attributedText: textSnapshot,
            selectedRanges: selectedRanges,
            columnSelectionRanges: columnSelectionRanges,
            columnSelectionAnchor: columnSelectionAnchor,
            columnSelectionWidth: columnSelectionWidth,
            alignmentLength: alignmentLength
        )
    }

    private func applyColumnEditState(_ state: ColumnEditState) {
        textStorage?.setAttributedString(state.attributedText)
        alignmentLength = state.alignmentLength
        setSelectedRanges(state.selectedRanges, affinity: .downstream, stillSelecting: false)
        columnSelectionRanges = state.columnSelectionRanges
        columnSelectionAnchor = state.columnSelectionAnchor
        columnSelectionWidth = state.columnSelectionWidth
        didChangeText()
    }

    private func registerColumnUndo(toRestore restoreState: ColumnEditState) {
        guard allowsUndo, let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { target in
            let redoState = target.captureColumnEditState()
            target.applyColumnEditState(restoreState)
            target.registerColumnUndo(toRestore: redoState)
        }
        undoManager.setActionName("Edit")
    }

    private func normalizedEdits(from ranges: [NSRange], rowCount: Int) -> [AlignmentEdit] {
        let lineSpan = alignmentLength + 1
        return ranges.compactMap { range in
            guard range.location >= 0 else { return nil }
            let row = range.location / lineSpan
            let column = range.location % lineSpan
            guard row >= 0, row < rowCount, column < alignmentLength else { return nil }
            let length = min(max(range.length, 0), alignmentLength - column)
            return AlignmentEdit(row: row, column: column, length: length)
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

    private func attributedSequenceText(from lines: [String]) -> NSAttributedString {
        NSAttributedString(
            string: lines.joined(separator: "\n") + "\n",
            attributes: [
                .font: font ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor.labelColor
            ]
        )
    }

    private func replaceCharacters(in line: inout String, column: Int, length: Int, with replacement: String) {
        let start = line.index(line.startIndex, offsetBy: min(column, line.count))
        let end = line.index(start, offsetBy: min(length, line.distance(from: start, to: line.endIndex)))
        line.replaceSubrange(start..<end, with: replacement)
    }

    private func insertCharacters(_ insertion: String, in line: inout String, column: Int) {
        let index = line.index(line.startIndex, offsetBy: min(max(column, 0), line.count))
        line.insert(contentsOf: insertion, at: index)
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
        guard isEditable else { return menu }
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

    func updateAlignmentDisplay(
        alignmentLength: Int,
        identityByColumn: [Double],
        majorityResidueByColumn: [UInt16],
        backgroundMode: AlignmentBackgroundMode,
        identityColorThreshold: Double
    ) {
        let needsRedraw =
            self.alignmentLength != alignmentLength ||
            self.identityByColumn.count != identityByColumn.count ||
            self.majorityResidueByColumn.count != majorityResidueByColumn.count ||
            self.backgroundMode != backgroundMode ||
            abs(self.identityColorThreshold - identityColorThreshold) > 0.001
        self.alignmentLength = alignmentLength
        self.identityByColumn = identityByColumn
        self.majorityResidueByColumn = majorityResidueByColumn
        self.backgroundMode = backgroundMode
        self.identityColorThreshold = identityColorThreshold
        if needsRedraw {
            needsDisplay = true
        }
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard alignmentLength > 0 else { return }
        guard let font else { return }

        let charWidth = max(("M" as NSString).size(withAttributes: [.font: font]).width, 1)
        let lineHeight = max(ceil(font.ascender - font.descender + font.leading), 1)
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
        case .residue:
            return ResiduePalette.backgroundColor(for: text.character(at: textIndex))
        case .different:
            let residue = normalizedResidueCode(text.character(at: textIndex))
            guard let majorityResidue = majorityResidueByColumn[safe: column], majorityResidue != 0 else { return nil }
            guard residue != majorityResidue else { return nil }
            return ResiduePalette.backgroundColor(for: residue)
        case .identity:
            return identityByColumn[safe: column].flatMap {
                IdentityPalette.backgroundColor(for: $0, threshold: identityColorThreshold)
            }
        }
    }
}
