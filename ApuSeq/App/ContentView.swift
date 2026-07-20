//
//  ContentView.swift
//  ApuSeq
//
//  Created by Ryo Suda on 2026/04/27.
//

import AppKit
import SwiftUI

struct ContentView: View {
    let document: ApuSeqDocument
    @AppStorage("appearanceMode") private var appearanceMode = AppAppearanceMode.system.rawValue

    var body: some View {
        RootView(document: document)
            .preferredColorScheme((AppAppearanceMode(rawValue: appearanceMode) ?? .system).colorScheme)
    }
}

private struct RootView: View {
    private enum ViewerMode: String, CaseIterable, Identifiable {
        case view = "View"
        case edit = "Edit"

        var id: String { rawValue }

        var localizedName: String {
            switch self {
            case .view:
                return String(localized: "View")
            case .edit:
                return String(localized: "Edit")
            }
        }
    }

    let document: ApuSeqDocument
    @Environment(\.documentConfiguration) private var documentConfiguration
    @Environment(\.undoManager) private var undoManager

    @State private var model = AlignmentViewModel()

    @AppStorage("alignmentFontSize") private var alignmentFontSize = 12.0
    @AppStorage("identityColorThreshold") private var identityColorThreshold = 0.5
    @AppStorage("showEditModeAutosaveWarning") private var showEditModeAutosaveWarning = true
    @State private var backgroundMode: AlignmentBackgroundMode = .residue
    @State private var displayOrderMode: AlignmentDisplayOrderMode = .original
    @State private var showsInspector = false
    @State private var selectedResidueCount = 0
    @State private var selectedSequenceCount = 0
    @State private var selectedStartPosition: Int?
    @State private var selectedEndPosition: Int?

    @AppStorage("showReferencePanel") private var showsReferencePanel = false
    @AppStorage("showConsensusPanel") private var showsConsensusPanel = false
    @AppStorage("showConservationPanel") private var showsConservationPanel = false

    @State private var selectedReferenceName: String?
    @State private var viewerMode: ViewerMode = .view

    private var needsIdentityByColumn: Bool {
        backgroundMode == .identity || showsConservationPanel
    }

    private var needsMajorityResidueByColumn: Bool {
        backgroundMode == .different
    }

    private var displayRows: [AlignmentRow] {
        model.displayedRows.isEmpty ? model.alignment.rows : model.displayedRows
    }

    private var effectiveDisplayOrderMode: AlignmentDisplayOrderMode {
        viewerMode == .view ? displayOrderMode : .original
    }

    private var canEditRenderedRows: Bool {
        viewerMode == .edit && model.renderedDisplayOrderMode == .original
    }

    private var canAddSequence: Bool {
        viewerMode == .edit && model.parseErrorMessage == nil
    }

    private var displayAlignment: AlignmentData {
        AlignmentData(
            format: model.alignment.format,
            rows: displayRows,
            length: model.alignment.length,
            sequenceKind: model.alignment.sequenceKind
        )
    }

    private var auxiliaryPanel: AuxiliaryPanelContent {
        model.auxiliaryPanelContent(
            referenceName: selectedReferenceName,
            showsReferencePanel: showsReferencePanel,
            showsConsensusPanel: showsConsensusPanel,
            showsConservationPanel: showsConservationPanel
        )
    }

    private var documentTitle: String {
        if let fileURL = documentConfiguration?.fileURL {
            return fileURL.lastPathComponent
        }
        return "Untitled"
    }

    private var translationContext: TranslationContext {
        return TranslationContext(
            rawText: document.rawText,
            sequenceKind: model.alignment.sequenceKind
        )
    }

    private var alignmentEditActions: AlignmentEditActions {
        AlignmentEditActions(
            canAddSequence: canAddSequence,
            addSequence: addSequence,
            canRemoveAllGapColumns: viewerMode == .edit && !model.alignment.rows.isEmpty && model.alignment.length > 0,
            removeAllGapColumns: removeAllGapColumns
        )
    }

    private var viewerModeBinding: Binding<ViewerMode> {
        Binding(
            get: { viewerMode },
            set: { setViewerMode($0) }
        )
    }

    private func auxiliaryAttributedText(_ text: String) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: alignmentFontSize, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
    }

    private func auxiliarySequenceAttributedText(_ content: AuxiliaryPanelContent) -> NSAttributedString {
        let attributed = NSMutableAttributedString(
            string: content.rightText,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: alignmentFontSize, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
        for range in content.coloredRanges {
            applyAuxiliaryBackground(to: attributed, in: range)
        }
        return attributed
    }

    private func applyAuxiliaryBackground(to attributed: NSMutableAttributedString, in range: NSRange) {
        guard range.length > 0 else { return }
        let text = attributed.string as NSString
        var runStart: Int?
        var runColor: NSColor?

        func flushRun(endOffset: Int) {
            guard let start = runStart, let color = runColor, endOffset > start else { return }
            attributed.addAttribute(
                .backgroundColor,
                value: color,
                range: NSRange(location: range.location + start, length: endOffset - start)
            )
        }

        for offset in 0..<range.length {
            let location = range.location + offset
            let color = auxiliaryBackgroundColor(for: text.character(at: location), column: offset)
            guard let color else {
                flushRun(endOffset: offset)
                runStart = nil
                runColor = nil
                continue
            }
            if runStart == nil {
                runStart = offset
                runColor = color
            } else if color != runColor {
                flushRun(endOffset: offset)
                runStart = offset
                runColor = color
            }
        }
        flushRun(endOffset: range.length)
    }

    private func auxiliaryBackgroundColor(for residue: UInt16, column: Int) -> NSColor? {
        switch backgroundMode {
        case .residue:
            return ResiduePalette.backgroundColor(for: residue)
        case .different:
            let normalizedResidue = normalizedResidueCode(residue)
            guard let majorityResidue = model.renderedAlignment.majorityResidueByColumn[safe: column], majorityResidue != 0 else { return nil }
            guard normalizedResidue != majorityResidue else { return nil }
            return ResiduePalette.backgroundColor(for: normalizedResidue)
        case .identity:
            return model.renderedAlignment.identityByColumn[safe: column].flatMap {
                IdentityPalette.backgroundColor(for: $0, threshold: identityColorThreshold)
            }
        }
    }

    var body: some View {
        Group {
            if let parseErrorMessage = model.parseErrorMessage {
                ContentUnavailableView(
                    String(localized: "Cannot Parse Alignment"),
                    systemImage: "exclamationmark.triangle",
                    description: Text(parseErrorMessage)
                )
            } else {
                VStack(spacing: 0) {
                    AlignmentTextViewport(
                        nameAttributedText: model.renderedAlignment.nameAttributedText,
                        sequenceAttributedText: model.renderedAlignment.sequenceAttributedText,
                        namesChecksum: model.renderedAlignment.namesChecksum,
                        sequenceChecksum: model.renderedAlignment.sequenceChecksum,
                        alignmentLength: displayAlignment.length,
                        identityByColumn: model.renderedAlignment.identityByColumn,
                        majorityResidueByColumn: model.renderedAlignment.majorityResidueByColumn,
                        backgroundMode: backgroundMode,
                        identityColorThreshold: identityColorThreshold,
                        fontSize: alignmentFontSize,
                        contentVersion: model.contentVersion,
                        defaultNameColumnWidth: model.renderedAlignment.nameColumnWidth,
                        displayedRowNames: displayRows.map(\.name),
                        auxiliaryNameAttributedText: auxiliaryAttributedText(auxiliaryPanel.leftText),
                        auxiliarySequenceAttributedText: auxiliarySequenceAttributedText(auxiliaryPanel),
                        auxiliaryLineCount: auxiliaryPanel.lineCount,
                        isEditMode: canEditRenderedRows,
                        onSequenceEdited: applyEditedSequenceText,
                        selectedResidueCount: $selectedResidueCount,
                        selectedSequenceCount: $selectedSequenceCount,
                        selectedStartPosition: $selectedStartPosition,
                        selectedEndPosition: $selectedEndPosition,
                        onAddSequence: addSequence,
                        onRenameSequence: renameDisplayedSequence,
                        onDeleteSequence: deleteDisplayedSequence
                    ) { selectedName in
                        selectedReferenceName = selectedName
                        if selectedName != nil {
                            showsReferencePanel = true
                        }
                    }
                    Divider()
                    FooterBar(
                        sequenceCount: displayAlignment.rows.count,
                        residueCount: displayAlignment.length,
                        selectedResidueCount: selectedResidueCount,
                        selectedSequenceCount: selectedSequenceCount,
                        selectedStartPosition: selectedStartPosition,
                        selectedEndPosition: selectedEndPosition,
                        backgroundMode: $backgroundMode,
                        displayOrderMode: $displayOrderMode,
                        canChangeDisplayOrder: viewerMode == .view
                    )
                }
            }
        }
        .navigationTitle(documentTitle)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Picker(String(localized: "Mode"), selection: viewerModeBinding) {
                    ForEach(ViewerMode.allCases) { mode in
                        Text(mode.localizedName).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .help(String(localized: "Switch between read-only view and edit mode"))

                Button {
                    addSequence()
                } label: {
                    Image(systemName: "plus")
                }
                .help(String(localized: "Add a sequence"))
                .disabled(!canAddSequence)

                Button {
                    showsInspector.toggle()
                } label: {
                    Image(systemName: "info.circle")
                }
                .help(String(localized: "Show alignment information"))
            }
        }
        .inspector(isPresented: $showsInspector) {
            FileInformationView(
                format: AppStrings.alignmentFormatName(model.alignment.format),
                sequenceCount: displayAlignment.rows.count,
                residueCount: displayAlignment.length,
                sourceCharacterCount: document.rawText.count
            )
        }
        .onAppear {
            markTranslatedDocumentAsEditedIfNeeded()
            parseAndRender()
        }
        .onChange(of: document.rawText) { _, _ in parseAndRender() }
        .onChange(of: backgroundMode) { _, newValue in
            if newValue == .identity || newValue == .different {
                rerender()
            }
        }
        .onChange(of: showsConservationPanel) { _, _ in rerender() }
        .onChange(of: alignmentFontSize) { _, _ in rerender() }
        .onChange(of: displayOrderMode) { _, _ in rerender() }
        .onChange(of: viewerMode) { _, _ in rerender() }
        .focusedSceneValue(\.translationContext, translationContext)
        .focusedSceneValue(\.alignmentEditActions, alignmentEditActions)
    }

    private func setViewerMode(_ mode: ViewerMode) {
        guard mode != viewerMode else { return }
        if mode == .edit, viewerMode != .edit, showEditModeAutosaveWarning {
            guard confirmEnteringEditMode() else { return }
        }
        viewerMode = mode
    }

    private func confirmEnteringEditMode() -> Bool {
        let alert = NSAlert()
        alert.messageText = String(localized: "Changes in Edit mode are autosaved with versions.")
        alert.informativeText = String(localized: "Editing can modify the document contents. macOS may autosave those changes and keep prior versions for recovery.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Enter Edit Mode"))
        alert.addButton(withTitle: AppStrings.cancel)
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = String(localized: "Do not show again")

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return false }
        if alert.suppressionButton?.state == .on {
            showEditModeAutosaveWarning = false
        }
        return true
    }

    private func parseAndRender() {
        if selectedReferenceName != nil, !model.containsRow(named: selectedReferenceName) {
            selectedReferenceName = nil
        }
        model.parseAndRender(
            rawText: document.rawText,
            fontSize: alignmentFontSize,
            needsIdentityByColumn: needsIdentityByColumn,
            needsMajorityResidueByColumn: needsMajorityResidueByColumn,
            displayOrderMode: effectiveDisplayOrderMode,
            referenceName: selectedReferenceName
        )
    }

    private func rerender() {
        model.rerender(
            fontSize: alignmentFontSize,
            needsIdentityByColumn: needsIdentityByColumn,
            needsMajorityResidueByColumn: needsMajorityResidueByColumn,
            displayOrderMode: effectiveDisplayOrderMode,
            referenceName: selectedReferenceName
        )
    }

    private func applyEditedSequenceText(_ editedText: String) {
        guard viewerMode == .edit else { return }
        guard let rebuilt = rebuildAlignment(fromEditedSequenceText: editedText) else { return }
        guard document.rawText != rebuilt else { return }
        document.rawText = rebuilt
    }

    private func addSequence() {
        guard canAddSequence else { return }
        let existingNames = Set(model.alignment.rows.map(\.name))
        guard let name = promptForSequenceName(
            title: AppStrings.addSequenceTitle,
            informativeText: String(localized: "Enter a name for the new sequence. You can type or paste the sequence directly in Edit mode after it is added."),
            defaultName: nextSequenceName(),
            existingNames: existingNames
        ) else { return }

        var rows = model.alignment.rows
        let newLength = max(model.alignment.length, 1)
        rows.append(AlignmentRow(name: name, sequence: String(repeating: "-", count: newLength)))
        applyDocumentRawText(rebuildAlignment(fromRows: rows), undoActionName: AppStrings.addSequenceTitle)
    }

    private func renameDisplayedSequence(at displayedRowIndex: Int) {
        guard viewerMode == .edit else { return }
        guard model.alignment.rows.indices.contains(displayedRowIndex) else { return }

        var rows = model.alignment.rows
        let oldName = rows[displayedRowIndex].name
        var existingNames = Set(rows.map(\.name))
        existingNames.remove(oldName)

        guard let newName = promptForSequenceName(
            title: AppStrings.renameSequenceTitle,
            informativeText: String(localized: "Enter a new name for this sequence."),
            defaultName: oldName,
            existingNames: existingNames
        ) else { return }
        guard newName != oldName else { return }

        rows[displayedRowIndex] = AlignmentRow(name: newName, sequence: rows[displayedRowIndex].sequence)
        if selectedReferenceName == oldName {
            selectedReferenceName = newName
        }
        applyDocumentRawText(rebuildAlignment(fromRows: rows), undoActionName: AppStrings.renameSequenceTitle)
    }

    private func deleteDisplayedSequence(at displayedRowIndex: Int) {
        guard viewerMode == .edit else { return }
        guard model.alignment.rows.count > 1 else { return }
        guard model.alignment.rows.indices.contains(displayedRowIndex) else { return }

        let rowToDelete = model.alignment.rows[displayedRowIndex]
        var rows = model.alignment.rows
        rows.remove(at: displayedRowIndex)

        if selectedReferenceName == rowToDelete.name {
            selectedReferenceName = nil
        }
        applyDocumentRawText(rebuildAlignment(fromRows: rows), undoActionName: AppStrings.deleteSequence)
    }

    private func removeAllGapColumns() {
        guard viewerMode == .edit else { return }
        guard let keepColumns = removableAllGapColumnMask() else { return }
        let keptColumnCount = keepColumns.filter(\.self).count

        let rows = model.alignment.rows.map { row in
            AlignmentRow(
                name: row.name,
                sequence: sequence(row.sequence, keepingColumns: keepColumns, keptColumnCount: keptColumnCount)
            )
        }
        applyDocumentRawText(rebuildAlignment(fromRows: rows), undoActionName: AppStrings.removeAllGapColumns)
    }

    private func removableAllGapColumnMask() -> [Bool]? {
        let rows = model.alignment.rows
        let length = model.alignment.length
        guard !rows.isEmpty, length > 0 else { return nil }

        let sequences = rows.map { $0.sequence as NSString }
        var keepColumns = Array(repeating: true, count: length)
        var removedCount = 0

        for column in 0..<length {
            let isAllGap = sequences.allSatisfy { sequence in
                guard column < sequence.length else { return true }
                return Self.isGap(sequence.character(at: column))
            }
            if isAllGap {
                keepColumns[column] = false
                removedCount += 1
            }
        }

        guard removedCount > 0, removedCount < length else { return nil }
        return keepColumns
    }

    private func sequence(_ sequence: String, keepingColumns keepColumns: [Bool], keptColumnCount: Int) -> String {
        let source = sequence as NSString
        var result = ""
        result.reserveCapacity(keptColumnCount)
        for (column, shouldKeep) in keepColumns.enumerated() where shouldKeep {
            guard column < source.length else { continue }
            result += source.substring(with: NSRange(location: column, length: 1))
        }
        return result
    }

    private static func isGap(_ residue: UInt16) -> Bool {
        residue == 45 || residue == 46
    }

    private func applyDocumentRawText(_ newText: String, undoActionName: String) {
        let currentText = document.rawText
        guard currentText != newText else { return }
        registerRawTextUndo(from: newText, to: currentText, actionName: undoActionName)
        document.rawText = newText
    }

    private func registerRawTextUndo(from currentText: String, to restoredText: String, actionName: String) {
        guard let undoManager else { return }
        Self.registerRawTextUndo(
            on: undoManager,
            document: document,
            from: currentText,
            to: restoredText,
            actionName: actionName
        )
    }

    private static func registerRawTextUndo(
        on undoManager: UndoManager,
        document: ApuSeqDocument,
        from currentText: String,
        to restoredText: String,
        actionName: String
    ) {
        undoManager.registerUndo(withTarget: document) { document in
            registerRawTextUndo(
                on: undoManager,
                document: document,
                from: restoredText,
                to: currentText,
                actionName: actionName
            )
            document.rawText = restoredText
        }
        undoManager.setActionName(actionName)
    }

    private func promptForSequenceName(
        title: String,
        informativeText: String,
        defaultName: String,
        existingNames: Set<String>
    ) -> String? {
        var currentValue = defaultName
        var currentInformativeText = informativeText

        while true {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = currentInformativeText
            alert.alertStyle = .informational
            alert.addButton(withTitle: AppStrings.ok)
            alert.addButton(withTitle: AppStrings.cancel)

            let textField = NSTextField(string: currentValue)
            textField.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
            alert.accessoryView = textField

            let response = alert.runModal()
            guard response == .alertFirstButtonReturn else { return nil }

            let name = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            currentValue = textField.stringValue
            if name.isEmpty {
                NSSound.beep()
                currentInformativeText = String(localized: "Sequence name cannot be empty.")
                continue
            }
            if existingNames.contains(name) {
                NSSound.beep()
                currentInformativeText = String(localized: "A sequence named \"\(name)\" already exists.")
                continue
            }
            return name
        }
    }

    private func nextSequenceName() -> String {
        let existingNames = Set(model.alignment.rows.map(\.name))
        var index = model.alignment.rows.count + 1
        while existingNames.contains("Sequence \(index)") {
            index += 1
        }
        return "Sequence \(index)"
    }

    private func rebuildAlignment(fromEditedSequenceText editedText: String) -> String? {
        var sequenceLines = editedText
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        if sequenceLines.last == "" {
            sequenceLines.removeLast()
        }
        guard sequenceLines.count == displayRows.count else { return nil }
        let rows = zip(displayRows, sequenceLines).map { row, sequence in
            AlignmentRow(name: row.name, sequence: sequence)
        }
        return rebuildAlignment(fromRows: rows)
    }

    private func rebuildAlignment(fromRows rows: [AlignmentRow]) -> String {
        AlignmentSerializer.serialize(rows: rows, preferredFormat: model.alignment.format)
    }

    private func markTranslatedDocumentAsEditedIfNeeded() {
        guard documentConfiguration?.fileURL == nil else { return }
        guard document.markEditedOnFirstDisplay else { return }
        document.markEditedOnFirstDisplay = false
        document.rawText += "\n"
    }
}

#Preview {
    ContentView(document: ApuSeqDocument())
}
