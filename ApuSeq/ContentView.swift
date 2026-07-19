//
//  ContentView.swift
//  ApuSeq
//
//  Created by 須田崚 on 2026/04/27.
//

import AppKit
import Observation
import SwiftUI

struct ContentView: View {
    @ObservedObject var document: ApuSeqDocument
    @AppStorage("appearanceMode") private var appearanceMode = AppAppearanceMode.system.rawValue

    var body: some View {
        RootView(document: document)
            .preferredColorScheme((AppAppearanceMode(rawValue: appearanceMode) ?? .system).colorScheme)
    }
}

@Observable
@MainActor
private final class AlignmentViewModel {
    var alignment: AlignmentData = .empty
    var renderedAlignment: RenderedAlignment = .empty
    var displayedRows: [AlignmentRow] = []
    var renderedDisplayOrderMode: AlignmentDisplayOrderMode = .original
    var parseErrorMessage: String?
    var contentVersion = 0

    private var alignmentVersion = 0
    private var parseTask: Task<Void, Never>?
    private var renderTask: Task<Void, Never>?
    private var cachedRenderVersion = -1
    private var cachedRenderFontSize = -1.0
    private var cachedRenderIdentityMode = false
    private var cachedRenderMajorityMode = false
    private var cachedRenderOrderMode: AlignmentDisplayOrderMode = .original
    private var cachedAlignment: RenderedAlignment?
    private var cachedDisplayedRows: [AlignmentRow] = []
    private var cachedConsensusKey: ConsensusKey?
    private var cachedConsensus: String = ""
    private var cachedAuxiliaryKey: AuxiliaryKey?
    private var cachedAuxiliaryContent: AuxiliaryPanelContent = .empty

    func parseAndRender(
        rawText: String,
        fontSize: Double,
        needsIdentityByColumn: Bool,
        needsMajorityResidueByColumn: Bool,
        displayOrderMode: AlignmentDisplayOrderMode,
        referenceName: String?
    ) {
        parseTask?.cancel()
        renderTask?.cancel()

        guard !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            alignment = .empty
            renderedAlignment = .empty
            displayedRows = []
            renderedDisplayOrderMode = .original
            parseErrorMessage = nil
            contentVersion += 1
            clearCache()
            return
        }

        parseTask = Task(priority: .userInitiated) {
            do {
                let parsed = try await runOnBackgroundThrowing {
                    try AlignmentParser.parse(rawText)
                }
                try Task.checkCancellation()
                await MainActor.run {
                    alignment = parsed
                    alignmentVersion += 1
                    parseErrorMessage = nil
                    clearCache()
                    rerender(
                        fontSize: fontSize,
                        needsIdentityByColumn: needsIdentityByColumn,
                        needsMajorityResidueByColumn: needsMajorityResidueByColumn,
                        displayOrderMode: displayOrderMode,
                        referenceName: referenceName
                    )
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    alignment = .empty
                    renderedAlignment = .empty
                    displayedRows = []
                    renderedDisplayOrderMode = .original
                    parseErrorMessage = error.localizedDescription
                    clearCache()
                    contentVersion += 1
                }
            }
        }
    }

    func rerender(
        fontSize: Double,
        needsIdentityByColumn: Bool,
        needsMajorityResidueByColumn: Bool,
        displayOrderMode: AlignmentDisplayOrderMode,
        referenceName: String?
    ) {
        renderTask?.cancel()

        let cacheKeyMatches =
            cachedRenderVersion == alignmentVersion &&
            abs(cachedRenderFontSize - fontSize) < 0.001 &&
            cachedRenderIdentityMode == needsIdentityByColumn &&
            cachedRenderMajorityMode == needsMajorityResidueByColumn &&
            cachedRenderOrderMode == displayOrderMode

        if !cacheKeyMatches {
            cachedRenderVersion = alignmentVersion
            cachedRenderFontSize = fontSize
            cachedRenderIdentityMode = needsIdentityByColumn
            cachedRenderMajorityMode = needsMajorityResidueByColumn
            cachedRenderOrderMode = displayOrderMode
            cachedAlignment = nil
            cachedDisplayedRows = []
        }

        if let cachedAlignment {
            apply(cachedAlignment, displayedRows: cachedDisplayedRows, displayOrderMode: displayOrderMode)
            return
        }

        let baseRows = alignment.rows
        let format = alignment.format
        let length = alignment.length
        let sequenceKind = alignment.sequenceKind
        let currentVersion = alignmentVersion

        renderTask = Task(priority: .userInitiated) {
            let renderResult: (RenderedAlignment, [AlignmentRow]) = await runOnBackground {
                let orderedRows = displayOrderMode == .upgma
                    ? AlignmentClusterer.upgmaOrderedRows(baseRows)
                    : baseRows
                let displayAlignment = AlignmentData(
                    format: format,
                    rows: orderedRows,
                    length: length,
                    sequenceKind: sequenceKind
                )
                let rendered = AlignmentRenderer.render(
                    displayAlignment,
                    needsIdentityByColumn: needsIdentityByColumn,
                    needsMajorityResidueByColumn: needsMajorityResidueByColumn,
                    fontSize: fontSize
                )
                return (rendered, orderedRows)
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard currentVersion == alignmentVersion else { return }
                cachedAlignment = renderResult.0
                cachedDisplayedRows = renderResult.1
                apply(renderResult.0, displayedRows: renderResult.1, displayOrderMode: displayOrderMode)
            }
        }
    }

    func row(named name: String?) -> AlignmentRow? {
        guard let name else { return nil }
        return alignment.rows.first(where: { $0.name == name })
    }

    func auxiliaryPanelContent(
        referenceName: String?,
        showsReferencePanel: Bool,
        showsConsensusPanel: Bool,
        showsConservationPanel: Bool
    ) -> AuxiliaryPanelContent {
        let key = AuxiliaryKey(
            alignmentVersion: alignmentVersion,
            referenceName: referenceName ?? "",
            showsReferencePanel: showsReferencePanel,
            showsConsensusPanel: showsConsensusPanel,
            showsConservationPanel: showsConservationPanel,
            identityCount: renderedAlignment.identityByColumn.count,
            identityChecksum: renderedAlignment.identityByColumn.reduce(into: 1469598103934665603) { partialResult, value in
                partialResult = (partialResult ^ UInt64(bitPattern: Int64(value.bitPattern))) &* 1099511628211
            }
        )
        if key == cachedAuxiliaryKey {
            return cachedAuxiliaryContent
        }

        let rows = alignment.rows
        let referenceText = showsReferencePanel ? (row(named: referenceName)?.sequence ?? "") : nil
        let consensus = showsConsensusPanel ? cachedConsensusSequence(rows: rows) : nil
        let conservation = showsConservationPanel ? renderedAlignment.identityByColumn : nil
        let built = AuxiliaryPanelBuilder.build(
            referenceLabel: showsReferencePanel ? "Ref: \(referenceName ?? "")" : nil,
            referenceSequence: referenceText,
            consensusSequence: consensus,
            conservation: conservation
        )
        cachedAuxiliaryKey = key
        cachedAuxiliaryContent = built
        return built
    }

    func containsRow(named name: String?) -> Bool {
        guard let name else { return false }
        return alignment.rows.contains(where: { $0.name == name })
    }

    private func apply(
        _ rendered: RenderedAlignment,
        displayedRows: [AlignmentRow],
        displayOrderMode: AlignmentDisplayOrderMode
    ) {
        renderedAlignment = rendered
        self.displayedRows = displayedRows
        renderedDisplayOrderMode = displayOrderMode
        contentVersion += 1
    }

    private func clearCache() {
        cachedAlignment = nil
        cachedDisplayedRows = []
        cachedRenderVersion = -1
        cachedRenderFontSize = -1.0
        cachedRenderIdentityMode = false
        cachedRenderMajorityMode = false
        cachedRenderOrderMode = .original
        cachedConsensusKey = nil
        cachedConsensus = ""
        cachedAuxiliaryKey = nil
        cachedAuxiliaryContent = .empty
    }

    private func cachedConsensusSequence(rows: [AlignmentRow]) -> String {
        let key = ConsensusKey(alignmentVersion: alignmentVersion)
        if key == cachedConsensusKey {
            return cachedConsensus
        }
        let sequence = AlignmentStatistics.consensusSequence(rows: rows, length: alignment.length)
        cachedConsensusKey = key
        cachedConsensus = sequence
        return sequence
    }

    private func runOnBackground<T>(_ work: @escaping () -> T) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: work())
            }
        }
    }

    private func runOnBackgroundThrowing<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try work())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private struct ConsensusKey: Equatable {
        let alignmentVersion: Int
    }

    private struct AuxiliaryKey: Equatable {
        let alignmentVersion: Int
        let referenceName: String
        let showsReferencePanel: Bool
        let showsConsensusPanel: Bool
        let showsConservationPanel: Bool
        let identityCount: Int
        let identityChecksum: UInt64
    }
}

enum AlignmentBackgroundMode: String, CaseIterable, Identifiable {
    case residue = "Residue"
    case different = "Different"
    case identity = "Identity"

    var id: String { rawValue }
}

enum AlignmentDisplayOrderMode: String, CaseIterable, Identifiable {
    case original = "Original"
    case upgma = "UPGMA"

    var id: String { rawValue }
}

private struct RootView: View {
    private enum ViewerMode: String, CaseIterable, Identifiable {
        case view = "View"
        case edit = "Edit"

        var id: String { rawValue }
    }

    @ObservedObject var document: ApuSeqDocument
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
        if let suggested = document.suggestedSaveFilename, !suggested.isEmpty {
            return suggested
        }
        return "Untitled"
    }

    private var translationContext: TranslationContext {
        let baseName = documentConfiguration?.fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
        return TranslationContext(
            rawText: document.rawText,
            sequenceKind: model.alignment.sequenceKind,
            fileBaseName: baseName,
            sourceDirectoryURL: documentConfiguration?.fileURL?.deletingLastPathComponent()
        )
    }

    private var alignmentEditActions: AlignmentEditActions {
        AlignmentEditActions(
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
                    "Cannot Parse Alignment",
                    systemImage: "exclamationmark.triangle",
                    description: Text(parseErrorMessage)
                )
            } else if model.alignment.rows.isEmpty {
                ContentUnavailableView(
                    "Open an Alignment",
                    systemImage: "doc.text",
                    description: Text("Supported formats: FASTA, CLUSTAL, plain text")
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
                Picker("Mode", selection: viewerModeBinding) {
                    ForEach(ViewerMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .help("Switch between read-only view and edit mode")

                Button {
                    showsInspector.toggle()
                } label: {
                    Image(systemName: "info.circle")
                }
                .help("Show alignment information")
            }
        }
        .inspector(isPresented: $showsInspector) {
            FileInformationView(
                format: model.alignment.format.rawValue,
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
        alert.messageText = "Changes in Edit mode are autosaved with versions."
        alert.informativeText = "Editing can modify the document contents. macOS may autosave those changes and keep prior versions for recovery."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Enter Edit Mode")
        alert.addButton(withTitle: "Cancel")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Do not show again"

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
        guard let rebuilt = rebuildFASTA(fromEditedSequenceText: editedText) else { return }
        guard document.rawText != rebuilt else { return }
        document.rawText = rebuilt
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
        applyDocumentRawText(rebuildFASTA(fromRows: rows), undoActionName: "Delete Sequence")
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
        applyDocumentRawText(rebuildFASTA(fromRows: rows), undoActionName: "Remove All-Gap Columns")
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

    private func rebuildFASTA(fromEditedSequenceText editedText: String) -> String? {
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
        return rebuildFASTA(fromRows: rows)
    }

    private func rebuildFASTA(fromRows rows: [AlignmentRow]) -> String {
        var output = ""
        let sequenceLength = rows.reduce(0) { $0 + $1.sequence.count }
        output.reserveCapacity(sequenceLength + (rows.count * 16))
        for row in rows {
            output += ">"
            output += row.name
            output += "\n"
            output += row.sequence
            output += "\n"
        }
        return output
    }

    private func markTranslatedDocumentAsEditedIfNeeded() {
        guard documentConfiguration?.fileURL == nil else { return }
        guard document.markEditedOnFirstDisplay else { return }
        document.markEditedOnFirstDisplay = false
        document.rawText += "\n"
    }
}

private struct AuxiliaryPanelContent {
    let leftText: String
    let rightText: String
    let lineCount: Int
    let coloredRanges: [NSRange]

    static let empty = AuxiliaryPanelContent(leftText: "", rightText: "", lineCount: 0, coloredRanges: [])
}

private enum AuxiliaryPanelBuilder {
    static func build(
        referenceLabel: String?,
        referenceSequence: String?,
        consensusSequence: String?,
        conservation: [Double]?
    ) -> AuxiliaryPanelContent {
        var left: [String] = []
        var right: [String] = []
        var rightUTF16Length = 0
        var coloredRanges: [NSRange] = []

        func appendLine(label: String, sequence: String, appliesColor: Bool = false) {
            if !right.isEmpty {
                rightUTF16Length += 1
            }
            if appliesColor {
                coloredRanges.append(NSRange(location: rightUTF16Length, length: (sequence as NSString).length))
            }
            left.append(label)
            right.append(sequence)
            rightUTF16Length += (sequence as NSString).length
        }

        if referenceSequence != nil {
            appendLine(label: referenceLabel ?? "Ref:", sequence: referenceSequence ?? "", appliesColor: true)
        }
        if let consensusSequence {
            appendLine(label: "Consensus", sequence: consensusSequence, appliesColor: true)
        }
        if let conservation {
            appendLine(label: "Identity", sequence: conservationBars(from: conservation))
        }

        return AuxiliaryPanelContent(
            leftText: left.joined(separator: "\n"),
            rightText: right.joined(separator: "\n"),
            lineCount: max(left.count, right.count),
            coloredRanges: coloredRanges
        )
    }

    private static func conservationBars(from values: [Double]) -> String {
        let glyphs: [Character] = [" ", "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]
        var output = String()
        output.reserveCapacity(values.count)
        for value in values {
            let clamped = min(max(value, 0), 1)
            let index = min(Int((clamped * 8.0).rounded()), 8)
            output.append(glyphs[index])
        }
        return output
    }
}

#Preview {
    ContentView(document: ApuSeqDocument())
}
