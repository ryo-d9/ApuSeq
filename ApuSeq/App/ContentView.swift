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
    @Environment(\.newDocument) private var newDocument
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
    @State private var sequenceNameSearchText = ""
    @State private var highlightedNameRowIndex: Int?
    @State private var nameSearchRequestID = 0
    @State private var showsSequenceNameFindBar = false
    @State private var sequenceNameFindFocusRequestID = 0
    @State private var sequenceNameSearchMessage: String?
    @State private var currentSequenceRowIndex: Int?
    @State private var isRunningMAFFTAlignment = false
    @State private var mafftAlignmentTask: Task<Void, Never>?
    @State private var mafftAlignmentErrorMessage = ""
    @State private var showsMAFFTAlignmentError = false
    @State private var operationErrorMessage = ""
    @State private var showsOperationError = false

    @SceneStorage("showReferencePanel") private var showsReferencePanel = false
    @SceneStorage("showConsensusPanel") private var showsConsensusPanel = false
    @SceneStorage("showConservationPanel") private var showsConservationPanel = false

    @State private var selectedReferenceName: String?
    @State private var viewerMode: ViewerMode = .view

    private var needsIdentityByColumn: Bool {
        backgroundMode == .identity || showsConservationPanel
    }

    private var needsMajorityResidueByColumn: Bool {
        backgroundMode == .minority
    }

    private var canDisplayReferenceBackground: Bool {
        selectedReferenceSequence != nil
    }

    private var selectedReferenceSequence: String? {
        model.row(named: selectedReferenceName)?.sequence
    }

    private var referenceSequenceForBackground: String? {
        backgroundMode == .reference ? selectedReferenceSequence : nil
    }

    private var availableBackgroundModes: [AlignmentBackgroundMode] {
        canDisplayReferenceBackground
            ? AlignmentBackgroundMode.allCases
            : AlignmentBackgroundMode.allCases.filter { $0 != .reference }
    }

    private var displayRows: [AlignmentRow] {
        model.displayedRows.isEmpty ? model.alignment.rows : model.displayedRows
    }

    private var currentSequenceRow: AlignmentRow? {
        guard let currentSequenceRowIndex,
              displayRows.indices.contains(currentSequenceRowIndex) else {
            return nil
        }
        return displayRows[currentSequenceRowIndex]
    }

    private var sequenceNameSearchStatusText: String? {
        if let sequenceNameSearchMessage {
            return sequenceNameSearchMessage
        }
        let query = sequenceNameSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }
        let matches = sequenceNameSearchMatches(for: query)
        guard !matches.isEmpty else {
            return String(localized: "No matches")
        }
        if let highlightedNameRowIndex,
           let ordinal = matches.firstIndex(of: highlightedNameRowIndex) {
            return "\(ordinal + 1)/\(matches.count)"
        }
        switch matches.count {
        case 1:
            return String(localized: "1 match")
        default:
            return String(format: String(localized: "%d matches"), matches.count)
        }
    }

    private var effectiveDisplayOrderMode: AlignmentDisplayOrderMode {
        viewerMode == .view ? displayOrderMode : .original
    }

    private var footerDisplayOrderMode: Binding<AlignmentDisplayOrderMode> {
        Binding(
            get: {
                viewerMode == .view ? displayOrderMode : .original
            },
            set: { newValue in
                displayOrderMode = newValue
            }
        )
    }

    private var backgroundModeBinding: Binding<AlignmentBackgroundMode> {
        Binding(
            get: { backgroundMode },
            set: { setBackgroundMode($0) }
        )
    }

    private var canEditRenderedRows: Bool {
        viewerMode == .edit && model.renderedDisplayOrderMode == .original
    }

    private var isPlainTextAlignment: Bool {
        model.alignment.format == .plainText
    }

    private var isEmptyDocument: Bool {
        document.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canCreateNamedAlignment: Bool {
        viewerMode == .edit && isEmptyDocument
    }

    private var canEditNamedAlignment: Bool {
        viewerMode == .edit && !isPlainTextAlignment
    }

    private var canUseNamedSequenceEditing: Bool {
        canCreateNamedAlignment || canEditNamedAlignment
    }

    private var canAddSequence: Bool {
        canUseNamedSequenceEditing && model.parseErrorMessage == nil
    }

    private var preferredFormatForNamedSequenceEditing: AlignmentFormat {
        isEmptyDocument ? .fasta : model.alignment.format
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

    private var sequenceTransformContext: SequenceTransformContext {
        return SequenceTransformContext(
            rawText: document.rawText,
            sequenceKind: model.alignment.sequenceKind
        )
    }

    private var alignmentEditActions: AlignmentEditActions {
        AlignmentEditActions(
            canAddSequence: canAddSequence,
            addSequence: addSequence,
            addFASTAFromClipboard: addFASTAFromClipboard,
            canInsertGapColumn: canEditRenderedRows && !model.alignment.rows.isEmpty,
            canRemoveAllGapColumns: viewerMode == .edit && !model.alignment.rows.isEmpty && model.alignment.length > 0,
            removeAllGapColumns: removeAllGapColumns,
            canTrimTrailingGaps: viewerMode == .edit && AlignmentColumnEditor.hasTrailingGaps(in: model.alignment.rows),
            trimTrailingGaps: trimTrailingGaps,
            canSortSequencesByName: canUseNamedSequenceEditing && model.alignment.rows.count > 1,
            canSortSequencesByUPGMA: canUseNamedSequenceEditing && AlignmentRowOrdering.canOrderWithUPGMA(rowCount: model.alignment.rows.count),
            sortSequences: sortSequences
        )
    }

    private var alignmentCopyActions: AlignmentCopyActions {
        AlignmentCopyActions(
            canCopyConsensus: !model.alignment.rows.isEmpty && model.alignment.length > 0,
            copyConsensus: copyConsensus,
            canCopySelectionAsFASTA: selectedResidueCount > 0 && !displayRows.isEmpty,
            copySelectionAsFASTA: copySelectionAsFASTA
        )
    }

    private var sequenceNameActions: SequenceNameActions {
        let hasCurrentSequence = currentSequenceRow != nil
        return SequenceNameActions(
            canFindSequenceName: !displayRows.isEmpty,
            findSequenceName: findSequenceName,
            canCopyCurrentSequence: hasCurrentSequence,
            copyCurrentSequence: copyCurrentSequence,
            canCopyCurrentSequenceAsFASTA: hasCurrentSequence,
            copyCurrentSequenceAsFASTA: copyCurrentSequenceAsFASTA,
            canRenameCurrentSequence: canUseNamedSequenceEditing && hasCurrentSequence,
            renameCurrentSequence: renameCurrentSequence,
            canDeleteCurrentSequence: canUseNamedSequenceEditing && hasCurrentSequence && model.alignment.rows.count > 1,
            deleteCurrentSequence: deleteCurrentSequence,
            canSetCurrentSequenceAsReference: hasCurrentSequence,
            setCurrentSequenceAsReference: setCurrentSequenceAsReference,
            canClearReference: selectedReferenceName != nil,
            clearReference: clearReference
        )
    }

    private var viewerModeActions: ViewerModeActions {
        ViewerModeActions(
            toggleTitle: viewerMode == .edit ? AppStrings.exitEditMode : AppStrings.enterEditMode,
            toggle: toggleViewerMode
        )
    }

    private var alignmentDisplayActions: AlignmentDisplayActions {
        AlignmentDisplayActions(
            showsReferencePanel: showsReferencePanel,
            toggleReferencePanel: { showsReferencePanel.toggle() },
            showsConsensusPanel: showsConsensusPanel,
            toggleConsensusPanel: { showsConsensusPanel.toggle() },
            showsConservationPanel: showsConservationPanel,
            toggleConservationPanel: { showsConservationPanel.toggle() },
            backgroundMode: backgroundMode,
            availableBackgroundModes: availableBackgroundModes,
            setBackgroundMode: setBackgroundMode,
            displayOrderMode: effectiveDisplayOrderMode,
            canChangeDisplayOrder: viewerMode == .view,
            canDisplayUPGMAOrder: AlignmentRowOrdering.canOrderWithUPGMA(rowCount: model.alignment.rows.count),
            setDisplayOrderMode: { displayOrderMode = $0 }
        )
    }

    private var mafftAlignmentActions: MAFFTAlignmentActions {
        MAFFTAlignmentActions(
            canAlign: canAlignWithMAFFT,
            align: startMAFFTAlignment,
            canAlignSelection: canAlignSelectedColumnsWithMAFFT,
            alignSelection: startSelectedColumnsMAFFTAlignment,
            canAlignAminoAcidGuidedNucleotide: canAlignAminoAcidGuidedNucleotide,
            alignAminoAcidGuidedNucleotide: startAminoAcidGuidedNucleotideAlignment,
            cancel: cancelMAFFTAlignment,
            isRunning: isRunningMAFFTAlignment
        )
    }

    private var canPrintAlignment: Bool {
        model.parseErrorMessage == nil && !displayRows.isEmpty && displayAlignment.length > 0
    }

    private var alignmentPrintActions: AlignmentPrintActions {
        AlignmentPrintActions(
            canPrint: canPrintAlignment,
            pageSetup: runPageSetup,
            print: printAlignment
        )
    }

    private var canAlignWithMAFFT: Bool {
        !isRunningMAFFTAlignment && !document.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canAlignSelectedColumnsWithMAFFT: Bool {
        guard viewerMode == .edit,
              !isPlainTextAlignment,
              !isRunningMAFFTAlignment,
              model.alignment.rows.count >= 2,
              selectedColumnRange != nil else {
            return false
        }
        return true
    }

    private var canAlignAminoAcidGuidedNucleotide: Bool {
        !isRunningMAFFTAlignment &&
        model.alignment.format == .fasta &&
        model.alignment.sequenceKind == .nucleotide &&
        model.alignment.rows.count >= 2
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
            applyAuxiliaryBackground(to: attributed, in: range, referenceSequence: referenceSequenceForBackground)
        }
        return attributed
    }

    private func applyAuxiliaryBackground(
        to attributed: NSMutableAttributedString,
        in range: NSRange,
        referenceSequence: String?
    ) {
        guard range.length > 0 else { return }
        let text = attributed.string as NSString
        let referenceText = referenceSequence.map { $0 as NSString }
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
            let referenceResidue = referenceText.flatMap { offset < $0.length ? $0.character(at: offset) : nil }
            let color = auxiliaryBackgroundColor(
                for: text.character(at: location),
                column: offset,
                referenceResidue: referenceResidue
            )
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

    private func auxiliaryBackgroundColor(for residue: UInt16, column: Int, referenceResidue: UInt16?) -> NSColor? {
        switch backgroundMode {
        case .none:
            return nil
        case .residue:
            return ResiduePalette.backgroundColor(for: residue)
        case .minority:
            let normalizedResidue = normalizedResidueCode(residue)
            guard let majorityResidue = model.renderedAlignment.majorityResidueByColumn[safe: column], majorityResidue != 0 else { return nil }
            guard normalizedResidue != majorityResidue else { return nil }
            return ResiduePalette.backgroundColor(for: normalizedResidue)
        case .reference:
            return ReferenceDifferencePalette.backgroundColor(for: residue, referenceResidue: referenceResidue)
        case .identity:
            return model.renderedAlignment.identityByColumn[safe: column].flatMap {
                IdentityPalette.backgroundColor(for: $0, threshold: identityColorThreshold)
            }
        }
    }

    private var alignmentViewport: AlignmentTextViewport {
        AlignmentTextViewport(
            nameAttributedText: model.renderedAlignment.nameAttributedText,
            sequenceAttributedText: model.renderedAlignment.sequenceAttributedText,
            namesChecksum: model.renderedAlignment.namesChecksum,
            sequenceChecksum: model.renderedAlignment.sequenceChecksum,
            alignmentLength: displayAlignment.length,
            identityByColumn: model.renderedAlignment.identityByColumn,
            majorityResidueByColumn: model.renderedAlignment.majorityResidueByColumn,
            backgroundMode: backgroundMode,
            referenceSequenceForBackground: referenceSequenceForBackground,
            identityColorThreshold: identityColorThreshold,
            fontSize: alignmentFontSize,
            contentVersion: model.contentVersion,
            defaultNameColumnWidth: model.renderedAlignment.nameColumnWidth,
            displayedRowNames: displayRows.map(\.name),
            displayedRowSequences: displayRows.map(\.sequence),
            highlightedNameRowIndex: highlightedNameRowIndex,
            nameSearchRequestID: nameSearchRequestID,
            isNameFindBarPresented: showsSequenceNameFindBar,
            nameSearchText: sequenceNameSearchText,
            nameSearchStatusText: sequenceNameSearchStatusText,
            nameFindFocusRequestID: sequenceNameFindFocusRequestID,
            auxiliaryNameAttributedText: auxiliaryAttributedText(auxiliaryPanel.leftText),
            auxiliarySequenceAttributedText: auxiliarySequenceAttributedText(auxiliaryPanel),
            auxiliaryLineCount: auxiliaryPanel.lineCount,
            isEditMode: canEditRenderedRows,
            canEditSequenceNames: canUseNamedSequenceEditing,
            onSequenceEdited: applyEditedSequenceText,
            selectedResidueCount: $selectedResidueCount,
            selectedSequenceCount: $selectedSequenceCount,
            selectedStartPosition: $selectedStartPosition,
            selectedEndPosition: $selectedEndPosition,
            currentSequenceRowIndex: $currentSequenceRowIndex,
            onAddSequence: addSequence,
            onAddFASTAFromClipboard: addFASTAFromClipboard,
            onRenameSequence: renameDisplayedSequence,
            onDeleteSequence: deleteDisplayedSequence,
            onSetReference: setReference,
            onNameFindTextChanged: updateSequenceNameSearchText,
            onNameFindSubmit: searchSequenceName,
            onNameFindClose: closeSequenceNameSearch
        )
    }

    var body: some View {
        contentBody
        .navigationTitle(documentTitle)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Picker(String(localized: "Mode"), selection: viewerModeBinding) {
                    ForEach(ViewerMode.allCases) { mode in
                        Text(mode.localizedName).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("viewer-mode-picker")
                .help(String(localized: "Switch between read-only view and edit mode"))

                if canUseNamedSequenceEditing {
                    Button {
                        addSequence()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityIdentifier("add-sequence-toolbar-button")
                    .accessibilityLabel(String(localized: "Add a sequence"))
                    .help(String(localized: "Add a sequence"))
                    .disabled(!canAddSequence)
                }

                Button {
                    showsInspector.toggle()
                } label: {
                    Image(systemName: "info.circle")
                }
                .accessibilityIdentifier("alignment-inspector-button")
                .accessibilityLabel(String(localized: "Show alignment information"))
                .help(String(localized: "Show alignment information"))
            }
        }
        .inspector(isPresented: $showsInspector) {
            FileInformationView(
                format: AppStrings.alignmentFormatName(model.alignment.format),
                sequenceKind: AppStrings.sequenceKindName(model.alignment.sequenceKind),
                sequenceCount: displayAlignment.rows.count,
                siteCount: displayAlignment.length,
                sourceCharacterCount: document.rawText.count,
                selectedSequenceCount: selectedSequenceCount,
                selectedSiteCount: selectedResidueCount,
                selectedStartPosition: selectedStartPosition,
                selectedEndPosition: selectedEndPosition,
                referenceName: selectedReferenceName,
                displayOrder: AppStrings.displayOrderName(effectiveDisplayOrderMode),
                background: AppStrings.backgroundName(backgroundMode)
            )
        }
        .sheet(isPresented: $isRunningMAFFTAlignment) {
            MAFFTAlignmentProgressView(cancel: cancelMAFFTAlignment)
                .interactiveDismissDisabled()
        }
        .alert(AppStrings.mafftAlignmentFailed, isPresented: $showsMAFFTAlignmentError) {
            Button(AppStrings.ok, role: .cancel) {}
        } message: {
            Text(mafftAlignmentErrorMessage)
        }
        .alert(AppStrings.operationFailed, isPresented: $showsOperationError) {
            Button(AppStrings.ok, role: .cancel) {}
        } message: {
            Text(operationErrorMessage)
        }
        .onAppear {
            parseAndRender()
        }
        .onDisappear {
            cancelMAFFTAlignment()
        }
        .onChange(of: document.rawText) { _, _ in parseAndRender() }
        .onChange(of: model.alignment.rows.count) { _, _ in
            validateDisplayOrderMode()
            validateCurrentSequenceRow()
            if showsSequenceNameFindBar {
                updateSequenceNameSearchHighlight(scrollToMatch: false)
            }
        }
        .onChange(of: backgroundMode) { _, newValue in
            if newValue == .identity || newValue == .minority {
                rerender()
            }
        }
        .onChange(of: showsConservationPanel) { _, _ in rerender() }
        .onChange(of: alignmentFontSize) { _, _ in rerender() }
        .onChange(of: displayOrderMode) { _, _ in rerender() }
        .onChange(of: viewerMode) { _, _ in rerender() }
        .focusedSceneValue(\.sequenceTransformContext, sequenceTransformContext)
        .focusedSceneValue(\.alignmentEditActions, alignmentEditActions)
        .focusedSceneValue(\.alignmentCopyActions, alignmentCopyActions)
        .focusedSceneValue(\.sequenceNameActions, sequenceNameActions)
        .focusedSceneValue(\.viewerModeActions, viewerModeActions)
        .focusedSceneValue(\.alignmentDisplayActions, alignmentDisplayActions)
        .focusedSceneValue(\.mafftAlignmentActions, mafftAlignmentActions)
        .focusedSceneValue(\.alignmentPrintActions, alignmentPrintActions)
    }

    @ViewBuilder
    private var contentBody: some View {
        if let parseErrorMessage = model.parseErrorMessage {
            ContentUnavailableView(
                String(localized: "Cannot Parse Alignment"),
                systemImage: "exclamationmark.triangle",
                description: Text(parseErrorMessage)
            )
        } else {
            VStack(spacing: 0) {
                alignmentViewport
                Divider()
                FooterBar(
                    sequenceCount: displayAlignment.rows.count,
                    residueCount: displayAlignment.length,
                    selectedResidueCount: selectedResidueCount,
                    selectedSequenceCount: selectedSequenceCount,
                    selectedStartPosition: selectedStartPosition,
                    selectedEndPosition: selectedEndPosition,
                    backgroundMode: backgroundModeBinding,
                    availableBackgroundModes: availableBackgroundModes,
                    displayOrderMode: footerDisplayOrderMode,
                    canChangeDisplayOrder: viewerMode == .view,
                    canDisplayUPGMAOrder: AlignmentRowOrdering.canOrderWithUPGMA(rowCount: model.alignment.rows.count)
                )
            }
        }
    }

    private func setViewerMode(_ mode: ViewerMode) {
        guard mode != viewerMode else { return }
        if mode == .edit, viewerMode != .edit, showEditModeAutosaveWarning {
            guard confirmEnteringEditMode() else { return }
        }
        viewerMode = mode
    }

    private func toggleViewerMode() {
        setViewerMode(viewerMode == .edit ? .view : .edit)
    }

    private func setBackgroundMode(_ mode: AlignmentBackgroundMode) {
        guard mode != .reference || canDisplayReferenceBackground else { return }
        backgroundMode = mode
    }

    private func setReference(_ selectedName: String?) {
        selectedReferenceName = selectedName
        if selectedName != nil {
            showsReferencePanel = true
        }
        validateReferenceBackgroundMode()
    }

    private func confirmEnteringEditMode() -> Bool {
        let alert = NSAlert()
        alert.messageText = AppStrings.editModeAutosaveWarningTitle
        alert.informativeText = AppStrings.editModeAutosaveWarningMessage
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
        validateReferenceBackgroundMode()
        model.parseAndRender(
            rawText: document.rawText,
            fontSize: alignmentFontSize,
            needsIdentityByColumn: needsIdentityByColumn,
            needsMajorityResidueByColumn: needsMajorityResidueByColumn,
            displayOrderMode: effectiveDisplayOrderMode,
            referenceName: selectedReferenceName
        )
        validateCurrentSequenceRow()
    }

    private func rerender() {
        model.rerender(
            fontSize: alignmentFontSize,
            needsIdentityByColumn: needsIdentityByColumn,
            needsMajorityResidueByColumn: needsMajorityResidueByColumn,
            displayOrderMode: effectiveDisplayOrderMode,
            referenceName: selectedReferenceName
        )
        validateCurrentSequenceRow()
    }

    private func runPageSetup() {
        NSPageLayout().runModal(with: NSPrintInfo.shared)
    }

    private func printAlignment() {
        guard canPrintAlignment else {
            NSSound.beep()
            return
        }
        AlignmentPrinter.runPrintPanel(
            alignment: displayAlignment,
            title: documentTitle,
            window: NSApp.keyWindow ?? NSApp.mainWindow
        )
    }

    private func validateDisplayOrderMode() {
        guard displayOrderMode == .upgma else { return }
        guard !AlignmentRowOrdering.canOrderWithUPGMA(rowCount: model.alignment.rows.count) else { return }
        displayOrderMode = .original
    }

    private func validateCurrentSequenceRow() {
        guard let currentSequenceRowIndex else { return }
        guard displayRows.indices.contains(currentSequenceRowIndex) else {
            self.currentSequenceRowIndex = nil
            return
        }
    }

    private func validateReferenceBackgroundMode() {
        if backgroundMode == .reference && !canDisplayReferenceBackground {
            backgroundMode = .residue
        }
    }

    private func applyEditedSequenceText(_ editedText: String) {
        guard viewerMode == .edit else { return }
        guard let rebuilt = rebuildAlignment(fromEditedSequenceText: editedText) else { return }
        guard document.rawText != rebuilt else { return }
        applyDocumentRawText(rebuilt, undoActionName: String(localized: "Edit"))
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

    private func addFASTAFromClipboard() {
        guard canAddSequence else { return }
        guard let clipboardText = NSPasteboard.general.string(forType: .string) else {
            showOperationError(AppStrings.clipboardDoesNotContainFASTA)
            return
        }
        let trimmed = clipboardText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(">"),
              let parsed = try? AlignmentParser.parse(trimmed),
              parsed.format == .fasta,
              !parsed.rows.isEmpty else {
            showOperationError(AppStrings.clipboardDoesNotContainFASTA)
            return
        }

        let rows = rowsByAppendingUniqueRows(parsed.rows)
        applyDocumentRawText(rebuildAlignment(fromRows: rows), undoActionName: AppStrings.addFASTAFromClipboard)
    }

    private func renameDisplayedSequence(at displayedRowIndex: Int) {
        guard canUseNamedSequenceEditing else { return }
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
        guard canUseNamedSequenceEditing else { return }
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

    private func renameCurrentSequence() {
        guard let currentSequenceRowIndex else { return }
        renameDisplayedSequence(at: currentSequenceRowIndex)
    }

    private func deleteCurrentSequence() {
        guard let currentSequenceRowIndex else { return }
        deleteDisplayedSequence(at: currentSequenceRowIndex)
    }

    private func removeAllGapColumns() {
        guard viewerMode == .edit else { return }
        guard let rows = AlignmentColumnEditor.removingAllGapColumns(
            from: model.alignment.rows,
            length: model.alignment.length
        ) else { return }
        applyDocumentRawText(rebuildAlignment(fromRows: rows), undoActionName: AppStrings.removeAllGapColumns)
    }

    private func trimTrailingGaps() {
        guard viewerMode == .edit else { return }
        guard let rows = AlignmentColumnEditor.trimmingTrailingGaps(from: model.alignment.rows) else { return }
        applyDocumentRawText(rebuildAlignment(fromRows: rows), undoActionName: AppStrings.trimTrailingGaps)
    }

    private func sortSequences(_ mode: AlignmentDisplayOrderMode) {
        guard canUseNamedSequenceEditing, model.alignment.rows.count > 1 else { return }

        let rows: [AlignmentRow]
        switch mode {
        case .original:
            return
        case .name:
            rows = AlignmentRowOrdering.nameOrderedRows(model.alignment.rows)
        case .upgma:
            guard AlignmentRowOrdering.canOrderWithUPGMA(rowCount: model.alignment.rows.count) else { return }
            rows = AlignmentRowOrdering.upgmaOrderedRows(model.alignment.rows)
        }

        guard !sameRowOrder(rows, model.alignment.rows) else { return }
        applyDocumentRawText(rebuildAlignment(fromRows: rows), undoActionName: AppStrings.sortSequences)
    }

    private func copyConsensus() {
        let consensus = model.consensusSequence()
        guard !consensus.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(consensus, forType: .string)
    }

    private func copySelectionAsFASTA() {
        guard selectedResidueCount > 0 else {
            NSSound.beep()
            return
        }
        guard NSApp.sendAction(NSSelectorFromString("copySelectionAsFASTA:"), to: nil, from: nil) else {
            NSSound.beep()
            return
        }
    }

    private func copyCurrentSequence() {
        guard let currentSequenceRow else {
            NSSound.beep()
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(currentSequenceRow.sequence, forType: .string)
    }

    private func copyCurrentSequenceAsFASTA() {
        guard let currentSequenceRow else {
            NSSound.beep()
            return
        }
        let fasta = AlignmentSerializer.serialize(rows: [currentSequenceRow], preferredFormat: .fasta)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(fasta, forType: .string)
    }

    private func setCurrentSequenceAsReference() {
        guard let currentSequenceRow else {
            NSSound.beep()
            return
        }
        setReference(currentSequenceRow.name)
    }

    private func clearReference() {
        setReference(nil)
    }

    private func findSequenceName() {
        guard !displayRows.isEmpty else { return }
        sequenceNameSearchMessage = nil
        showsSequenceNameFindBar = true
        sequenceNameFindFocusRequestID += 1
        updateSequenceNameSearchHighlight(scrollToMatch: true)
    }

    private func updateSequenceNameSearchText(_ text: String) {
        sequenceNameSearchText = text
        sequenceNameSearchMessage = nil
        updateSequenceNameSearchHighlight(scrollToMatch: true)
    }

    private func closeSequenceNameSearch() {
        showsSequenceNameFindBar = false
        highlightedNameRowIndex = nil
        sequenceNameSearchMessage = nil
    }

    private func updateSequenceNameSearchHighlight(scrollToMatch: Bool) {
        guard !displayRows.isEmpty else { return }
        let searchText = sequenceNameSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !searchText.isEmpty else {
            highlightedNameRowIndex = nil
            sequenceNameSearchMessage = nil
            return
        }

        guard let matchedIndex = sequenceNameSearchMatches(for: searchText).first else {
            highlightedNameRowIndex = nil
            sequenceNameSearchMessage = nil
            return
        }

        sequenceNameSearchMessage = nil
        highlightedNameRowIndex = matchedIndex
        if scrollToMatch {
            nameSearchRequestID += 1
        }
    }

    private func searchSequenceName(direction: Int) {
        guard !displayRows.isEmpty else { return }
        let searchText = sequenceNameSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        sequenceNameSearchText = searchText
        guard !searchText.isEmpty else {
            sequenceNameSearchMessage = String(localized: "Enter part of a sequence name.")
            highlightedNameRowIndex = nil
            return
        }

        let matches = sequenceNameSearchMatches(for: searchText)
        guard !matches.isEmpty else {
            NSSound.beep()
            sequenceNameSearchMessage = nil
            highlightedNameRowIndex = nil
            return
        }

        let step = direction < 0 ? -1 : 1
        let currentMatchIndex = highlightedNameRowIndex.flatMap { matches.firstIndex(of: $0) }
        let nextMatchIndex: Int
        if let currentMatchIndex {
            nextMatchIndex = (currentMatchIndex + step + matches.count) % matches.count
        } else {
            nextMatchIndex = direction < 0 ? matches.count - 1 : 0
        }
        sequenceNameSearchMessage = nil
        highlightedNameRowIndex = matches[nextMatchIndex]
        nameSearchRequestID += 1
    }

    private func sequenceNameSearchMatches(for searchText: String) -> [Int] {
        displayRows.indices.filter {
            displayRows[$0].name.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func startMAFFTAlignment() {
        guard canAlignWithMAFFT else { return }
        let rawText = document.rawText
        isRunningMAFFTAlignment = true
        mafftAlignmentTask = Task { @MainActor in
            do {
                let aligned = try await MAFFTAligner.alignAuto(rawText: rawText)
                guard !Task.isCancelled else { return }
                finishMAFFTAlignment()
                newDocument {
                    ApuSeqDocument(rawText: aligned)
                }
            } catch is CancellationError {
                finishMAFFTAlignment()
            } catch {
                finishMAFFTAlignment()
                mafftAlignmentErrorMessage = error.localizedDescription
                showsMAFFTAlignmentError = true
            }
        }
    }

    private func startSelectedColumnsMAFFTAlignment() {
        guard canAlignSelectedColumnsWithMAFFT else { return }
        guard let columnRange = selectedColumnRange else { return }
        let rows = model.alignment.rows
        isRunningMAFFTAlignment = true
        mafftAlignmentTask = Task { @MainActor in
            do {
                let realignedRows = try await AlignmentRangeRealigner.realignSelectedColumns(
                    rows: rows,
                    columnRange: columnRange
                )
                guard !Task.isCancelled else { return }
                finishMAFFTAlignment()
                applyDocumentRawText(
                    rebuildAlignment(fromRows: realignedRows),
                    undoActionName: AppStrings.alignSelectedColumnsWithMAFFTAuto
                )
            } catch is CancellationError {
                finishMAFFTAlignment()
            } catch {
                finishMAFFTAlignment()
                mafftAlignmentErrorMessage = error.localizedDescription
                showsMAFFTAlignmentError = true
            }
        }
    }

    private func startAminoAcidGuidedNucleotideAlignment(frameOffset: Int, codonTable: TranslationCodonTable) {
        guard canAlignAminoAcidGuidedNucleotide else { return }
        let rawText = document.rawText
        isRunningMAFFTAlignment = true
        mafftAlignmentTask = Task { @MainActor in
            do {
                let aligned = try await AminoAcidGuidedNucleotideAligner.align(
                    rawText: rawText,
                    frameOffset: frameOffset,
                    codonTable: codonTable
                )
                guard !Task.isCancelled else { return }
                finishMAFFTAlignment()
                newDocument {
                    ApuSeqDocument(rawText: aligned)
                }
            } catch is CancellationError {
                finishMAFFTAlignment()
            } catch {
                finishMAFFTAlignment()
                mafftAlignmentErrorMessage = error.localizedDescription
                showsMAFFTAlignmentError = true
            }
        }
    }

    private func cancelMAFFTAlignment() {
        mafftAlignmentTask?.cancel()
    }

    private func finishMAFFTAlignment() {
        isRunningMAFFTAlignment = false
        mafftAlignmentTask = nil
    }

    private func showOperationError(_ message: String) {
        operationErrorMessage = message
        showsOperationError = true
    }

    private var selectedColumnRange: Range<Int>? {
        guard let selectedStartPosition, let selectedEndPosition else { return nil }
        let lower = min(selectedStartPosition, selectedEndPosition) - 1
        let upper = max(selectedStartPosition, selectedEndPosition)
        guard lower >= 0, lower < upper, upper <= model.alignment.length else { return nil }
        return lower..<upper
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

    private func rowsByAppendingUniqueRows(_ rowsToAppend: [AlignmentRow]) -> [AlignmentRow] {
        var existingNames = Set(model.alignment.rows.map(\.name))
        var rows = model.alignment.rows
        rows.reserveCapacity(rows.count + rowsToAppend.count)

        for row in rowsToAppend {
            let name = uniqueSequenceName(row.name, existingNames: &existingNames)
            rows.append(AlignmentRow(name: name, sequence: row.sequence))
        }
        return rows
    }

    private func uniqueSequenceName(_ name: String, existingNames: inout Set<String>) -> String {
        guard existingNames.contains(name) else {
            existingNames.insert(name)
            return name
        }

        var index = 2
        var candidate = "\(name) \(index)"
        while existingNames.contains(candidate) {
            index += 1
            candidate = "\(name) \(index)"
        }
        existingNames.insert(candidate)
        return candidate
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
        AlignmentSerializer.serialize(rows: rows, preferredFormat: preferredFormatForNamedSequenceEditing)
    }

    private func sameRowOrder(_ first: [AlignmentRow], _ second: [AlignmentRow]) -> Bool {
        first.elementsEqual(second) { left, right in
            left.name == right.name && left.sequence == right.sequence
        }
    }
}

private struct MAFFTAlignmentProgressView: View {
    let cancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.regular)

            Text(AppStrings.aligningWithMAFFT)
                .font(.headline)

            Button(AppStrings.cancel) {
                cancel()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(24)
        .frame(width: 320)
    }
}

#Preview {
    ContentView(document: ApuSeqDocument())
}
