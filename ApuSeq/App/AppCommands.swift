import AppKit
import SwiftUI

struct SequenceTransformContext {
    let rawText: String
    let sequenceKind: SequenceKind
}

struct AlignmentEditActions {
    let canAddSequence: Bool
    let addSequence: () -> Void
    let addFASTAFromClipboard: () -> Void
    let canInsertGapColumn: Bool
    let canRemoveAllGapColumns: Bool
    let removeAllGapColumns: () -> Void
    let canTrimTrailingGaps: Bool
    let trimTrailingGaps: () -> Void
    let canSortSequencesByName: Bool
    let canSortSequencesByUPGMA: Bool
    let sortSequences: (AlignmentDisplayOrderMode) -> Void
}

struct AlignmentCopyActions {
    let canCopyConsensus: Bool
    let copyConsensus: () -> Void
    let canCopySelectionAsFASTA: Bool
    let copySelectionAsFASTA: () -> Void
}

struct AlignmentPrintActions {
    let canPrint: Bool
    let pageSetup: () -> Void
    let print: () -> Void
}

struct SequenceNameActions {
    let canFindSequenceName: Bool
    let findSequenceName: () -> Void
    let canCopyCurrentSequence: Bool
    let copyCurrentSequence: () -> Void
    let canCopyCurrentSequenceAsFASTA: Bool
    let copyCurrentSequenceAsFASTA: () -> Void
    let canRenameCurrentSequence: Bool
    let renameCurrentSequence: () -> Void
    let canDeleteCurrentSequence: Bool
    let deleteCurrentSequence: () -> Void
    let canSetCurrentSequenceAsReference: Bool
    let setCurrentSequenceAsReference: () -> Void
    let canClearReference: Bool
    let clearReference: () -> Void
}

struct ViewerModeActions {
    let toggleTitle: String
    let toggle: () -> Void
}

struct AlignmentDisplayActions {
    let showsReferencePanel: Bool
    let toggleReferencePanel: () -> Void
    let showsConsensusPanel: Bool
    let toggleConsensusPanel: () -> Void
    let showsConservationPanel: Bool
    let toggleConservationPanel: () -> Void
    let backgroundMode: AlignmentBackgroundMode
    let availableBackgroundModes: [AlignmentBackgroundMode]
    let setBackgroundMode: (AlignmentBackgroundMode) -> Void
    let displayOrderMode: AlignmentDisplayOrderMode
    let canChangeDisplayOrder: Bool
    let canDisplayUPGMAOrder: Bool
    let setDisplayOrderMode: (AlignmentDisplayOrderMode) -> Void
}

struct MAFFTAlignmentActions {
    let canAlign: Bool
    let align: () -> Void
    let canAlignSelection: Bool
    let alignSelection: () -> Void
    let canAlignAminoAcidGuidedNucleotide: Bool
    let alignAminoAcidGuidedNucleotide: (Int, TranslationCodonTable) -> Void
    let cancel: () -> Void
    let isRunning: Bool
}

private struct SequenceTransformContextKey: FocusedValueKey {
    typealias Value = SequenceTransformContext
}

private struct AlignmentEditActionsKey: FocusedValueKey {
    typealias Value = AlignmentEditActions
}

private struct AlignmentCopyActionsKey: FocusedValueKey {
    typealias Value = AlignmentCopyActions
}

private struct AlignmentPrintActionsKey: FocusedValueKey {
    typealias Value = AlignmentPrintActions
}

private struct SequenceNameActionsKey: FocusedValueKey {
    typealias Value = SequenceNameActions
}

private struct ViewerModeActionsKey: FocusedValueKey {
    typealias Value = ViewerModeActions
}

private struct AlignmentDisplayActionsKey: FocusedValueKey {
    typealias Value = AlignmentDisplayActions
}

private struct MAFFTAlignmentActionsKey: FocusedValueKey {
    typealias Value = MAFFTAlignmentActions
}

extension FocusedValues {
    var sequenceTransformContext: SequenceTransformContext? {
        get { self[SequenceTransformContextKey.self] }
        set { self[SequenceTransformContextKey.self] = newValue }
    }

    var alignmentEditActions: AlignmentEditActions? {
        get { self[AlignmentEditActionsKey.self] }
        set { self[AlignmentEditActionsKey.self] = newValue }
    }

    var alignmentCopyActions: AlignmentCopyActions? {
        get { self[AlignmentCopyActionsKey.self] }
        set { self[AlignmentCopyActionsKey.self] = newValue }
    }

    var alignmentPrintActions: AlignmentPrintActions? {
        get { self[AlignmentPrintActionsKey.self] }
        set { self[AlignmentPrintActionsKey.self] = newValue }
    }

    var sequenceNameActions: SequenceNameActions? {
        get { self[SequenceNameActionsKey.self] }
        set { self[SequenceNameActionsKey.self] = newValue }
    }

    var viewerModeActions: ViewerModeActions? {
        get { self[ViewerModeActionsKey.self] }
        set { self[ViewerModeActionsKey.self] = newValue }
    }

    var alignmentDisplayActions: AlignmentDisplayActions? {
        get { self[AlignmentDisplayActionsKey.self] }
        set { self[AlignmentDisplayActionsKey.self] = newValue }
    }

    var mafftAlignmentActions: MAFFTAlignmentActions? {
        get { self[MAFFTAlignmentActionsKey.self] }
        set { self[MAFFTAlignmentActionsKey.self] = newValue }
    }
}

struct ColumnSelectionCommands: Commands {
    @FocusedValue(\.alignmentCopyActions) private var actions

    var body: some Commands {
        CommandGroup(after: .pasteboard) {
            Button(AppStrings.copySelectionAsFASTA) {
                actions?.copySelectionAsFASTA()
            }
            .keyboardShortcut("c", modifiers: [.command, .option])
            .disabled(actions?.canCopySelectionAsFASTA != true)

            Button(AppStrings.copyConsensus) {
                actions?.copyConsensus()
            }
            .disabled(actions?.canCopyConsensus != true)
        }

        CommandGroup(after: .textEditing) {
            Divider()
            Menu(AppStrings.select) {
                Button(AppStrings.selectUngappedChunk) {
                    _ = NSApp.sendAction(NSSelectorFromString("selectWord:"), to: nil, from: nil)
                }

                Button(AppStrings.selectLine) {
                    _ = NSApp.sendAction(NSSelectorFromString("selectLine:"), to: nil, from: nil)
                }

                Divider()
                Button(String(localized: "Select Column Up")) {
                    _ = NSApp.sendAction(NSSelectorFromString("selectColumnUp:"), to: nil, from: nil)
                }
                .keyboardShortcut(.upArrow, modifiers: [.control, .shift])

                Button(String(localized: "Select Column Down")) {
                    _ = NSApp.sendAction(NSSelectorFromString("selectColumnDown:"), to: nil, from: nil)
                }
                .keyboardShortcut(.downArrow, modifiers: [.control, .shift])
            }
        }
    }
}

struct SequenceNameCommands: Commands {
    @FocusedValue(\.sequenceNameActions) private var actions

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Button(AppStrings.findSequenceName) {
                actions?.findSequenceName()
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .disabled(actions?.canFindSequenceName != true)
        }
    }
}

struct AlignmentEditCommands: Commands {
    @FocusedValue(\.alignmentEditActions) private var actions

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Button(AppStrings.addSequence) {
                actions?.addSequence()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(actions?.canAddSequence != true)

            Button(AppStrings.addFASTAFromClipboard) {
                actions?.addFASTAFromClipboard()
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])
            .disabled(actions?.canAddSequence != true)

            Button(AppStrings.insertGapColumn) {
                _ = NSApp.sendAction(NSSelectorFromString("insertGapColumn:"), to: nil, from: nil)
            }
            .keyboardShortcut("-", modifiers: [.command, .shift])
            .disabled(actions?.canInsertGapColumn != true)
        }
    }
}

struct ViewerModeCommands: Commands {
    @FocusedValue(\.viewerModeActions) private var actions

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button(actions?.toggleTitle ?? AppStrings.enterEditMode) {
                actions?.toggle()
            }
            .keyboardShortcut("e", modifiers: [.command, .option])
            .disabled(actions == nil)
        }
    }
}

struct ViewPanelCommands: Commands {
    @FocusedValue(\.alignmentDisplayActions) private var displayActions

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Divider()
            Button(displayActions?.showsReferencePanel == true ? String(localized: "Hide Reference Panel") : String(localized: "Show Reference Panel")) {
                displayActions?.toggleReferencePanel()
            }
            .keyboardShortcut("r", modifiers: [.command, .control])
            .disabled(displayActions == nil)

            Button(displayActions?.showsConsensusPanel == true ? String(localized: "Hide Consensus Panel") : String(localized: "Show Consensus Panel")) {
                displayActions?.toggleConsensusPanel()
            }
            .keyboardShortcut("c", modifiers: [.command, .control])
            .disabled(displayActions == nil)

            Button(displayActions?.showsConservationPanel == true ? String(localized: "Hide Identity Panel") : String(localized: "Show Identity Panel")) {
                displayActions?.toggleConservationPanel()
            }
            .keyboardShortcut("i", modifiers: [.command, .control])
            .disabled(displayActions == nil)

            Divider()
            Picker(String(localized: "Background Color"), selection: backgroundModeBinding) {
                ForEach(displayActions?.availableBackgroundModes ?? [.residue]) { mode in
                    Text(mode.localizedName).tag(mode)
                }
            }
            .disabled(displayActions == nil)

            Picker(String(localized: "Display Order"), selection: displayOrderModeBinding) {
                ForEach(AlignmentDisplayOrderMode.allCases) { mode in
                    Text(mode.localizedName).tag(mode)
                        .disabled(mode == .upgma && displayActions?.canDisplayUPGMAOrder != true)
                }
            }
            .disabled(displayActions?.canChangeDisplayOrder != true)
        }
    }

    private var backgroundModeBinding: Binding<AlignmentBackgroundMode> {
        Binding(
            get: { displayActions?.backgroundMode ?? .residue },
            set: { displayActions?.setBackgroundMode($0) }
        )
    }

    private var displayOrderModeBinding: Binding<AlignmentDisplayOrderMode> {
        Binding(
            get: { displayActions?.displayOrderMode ?? .original },
            set: { displayActions?.setDisplayOrderMode($0) }
        )
    }
}

struct OpenSourceLicenseCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .help) {
            Button(AppStrings.openSourceLicensesMenuItem) {
                openWindow(id: OpenSourceLicensesView.windowID)
            }
        }
    }
}

struct AlignmentPrintCommands: Commands {
    @FocusedValue(\.alignmentPrintActions) private var actions

    var body: some Commands {
        CommandGroup(replacing: .printItem) {
            Button(String(localized: "Page Setup…")) {
                actions?.pageSetup()
            }
            .disabled(actions == nil)

            Button(String(localized: "Print…")) {
                actions?.print()
            }
            .keyboardShortcut("p", modifiers: [.command])
            .disabled(actions?.canPrint != true)
        }
    }
}

struct AlignmentCommands: Commands {
    @FocusedValue(\.alignmentEditActions) private var editActions
    @FocusedValue(\.sequenceNameActions) private var sequenceNameActions
    @FocusedValue(\.mafftAlignmentActions) private var mafftActions
    @FocusedValue(\.sequenceTransformContext) private var context
    @Environment(\.newDocument) private var newDocument
    @AppStorage("translationCodonTable") private var translationCodonTable = TranslationCodonTable.standard.rawValue

    var body: some Commands {
        CommandMenu(AppStrings.alignment) {
            if canUseAnyMAFFTAlignment {
                Menu(AppStrings.alignWithMAFFT) {
                    Button(AppStrings.alignEntireAlignment) {
                        mafftActions?.align()
                    }
                    .disabled(mafftActions?.canAlign != true)

                    Button(AppStrings.alignSelectedColumns) {
                        mafftActions?.alignSelection()
                    }
                    .disabled(mafftActions?.canAlignSelection != true)

                    if mafftActions?.canAlignAminoAcidGuidedNucleotide == true {
                        Menu(AppStrings.aminoAcidGuidedNucleotideAlignment) {
                            Button(String(localized: "Frame +0")) {
                                runAminoAcidGuidedNucleotideAlignment(frameOffset: 0)
                            }
                            Button(String(localized: "Frame +1")) {
                                runAminoAcidGuidedNucleotideAlignment(frameOffset: 1)
                            }
                            Button(String(localized: "Frame +2")) {
                                runAminoAcidGuidedNucleotideAlignment(frameOffset: 2)
                            }
                        }
                    } else {
                        Button(AppStrings.aminoAcidGuidedNucleotideAlignment) {}
                            .disabled(true)
                    }
                }
            } else {
                Button(AppStrings.alignWithMAFFT) {}
                    .disabled(true)
            }

            Button(AppStrings.removeAllGapColumns) {
                editActions?.removeAllGapColumns()
            }
            .keyboardShortcut(.delete, modifiers: [.command, .shift])
            .disabled(editActions?.canRemoveAllGapColumns != true)

            Button(AppStrings.trimTrailingGaps) {
                editActions?.trimTrailingGaps()
            }
            .disabled(editActions?.canTrimTrailingGaps != true)

            Menu(AppStrings.sortSequences) {
                Button(AppStrings.sortSequencesByName) {
                    editActions?.sortSequences(.name)
                }
                .disabled(editActions?.canSortSequencesByName != true)

                Button(AppStrings.sortSequencesByUPGMA) {
                    editActions?.sortSequences(.upgma)
                }
                .disabled(editActions?.canSortSequencesByUPGMA != true)
            }
            .disabled(editActions?.canSortSequencesByName != true && editActions?.canSortSequencesByUPGMA != true)

            Menu(AppStrings.currentSequenceMenu) {
                Button(AppStrings.copyCurrentSequence) {
                    sequenceNameActions?.copyCurrentSequence()
                }
                .disabled(sequenceNameActions?.canCopyCurrentSequence != true)

                Button(AppStrings.copyCurrentSequenceAsFASTA) {
                    sequenceNameActions?.copyCurrentSequenceAsFASTA()
                }
                .disabled(sequenceNameActions?.canCopyCurrentSequenceAsFASTA != true)

                Divider()

                Button(AppStrings.setCurrentSequenceAsReference) {
                    sequenceNameActions?.setCurrentSequenceAsReference()
                }
                .disabled(sequenceNameActions?.canSetCurrentSequenceAsReference != true)

                Button(AppStrings.clearReference) {
                    sequenceNameActions?.clearReference()
                }
                .disabled(sequenceNameActions?.canClearReference != true)

                Divider()

                Button(AppStrings.renameCurrentSequence) {
                    sequenceNameActions?.renameCurrentSequence()
                }
                .disabled(sequenceNameActions?.canRenameCurrentSequence != true)

                Button(AppStrings.deleteCurrentSequence) {
                    sequenceNameActions?.deleteCurrentSequence()
                }
                .disabled(sequenceNameActions?.canDeleteCurrentSequence != true)
            }
            .disabled(sequenceNameActions == nil)

            Divider()

            Button(AppStrings.reverseComplement) {
                runReverseComplement()
            }
            .disabled(!canReverseComplement)

            if canTranslate {
                Menu(String(localized: "Translation")) {
                    Button(String(localized: "Frame +0")) { runTranslation(frameOffset: 0) }
                        .keyboardShortcut("0", modifiers: [.command, .option])
                    Button(String(localized: "Frame +1")) { runTranslation(frameOffset: 1) }
                    Button(String(localized: "Frame +2")) { runTranslation(frameOffset: 2) }
                }
            } else {
                Button(String(localized: "Translation")) {}
                    .disabled(true)
            }
        }
    }

    private var canUseAnyMAFFTAlignment: Bool {
        mafftActions?.canAlign == true ||
        mafftActions?.canAlignSelection == true ||
        mafftActions?.canAlignAminoAcidGuidedNucleotide == true
    }

    private var canReverseComplement: Bool {
        guard let context else { return false }
        return context.sequenceKind == .nucleotide && !context.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canTranslate: Bool {
        guard let context else { return false }
        return context.sequenceKind == .nucleotide && !context.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func runReverseComplement() {
        guard let context else { return }
        Task {
            do {
                let reverseComplemented = try AlignmentReverseComplementer.reverseComplementFASTA(
                    rawText: context.rawText
                )
                await MainActor.run {
                    newDocument {
                        ApuSeqDocument(rawText: reverseComplemented)
                    }
                }
            } catch {
                presentOperationError(error.localizedDescription)
            }
        }
    }

    private func runTranslation(frameOffset: Int) {
        guard let context else { return }
        let codonTable = TranslationCodonTable(rawValue: translationCodonTable) ?? .standard
        Task {
            do {
                let translated = try AlignmentTranslator.translateFASTA(
                    rawText: context.rawText,
                    frameOffset: frameOffset,
                    codonTable: codonTable
                )
                await MainActor.run {
                    newDocument {
                        ApuSeqDocument(rawText: translated)
                    }
                }
            } catch {
                presentOperationError(error.localizedDescription)
            }
        }
    }

    private func runAminoAcidGuidedNucleotideAlignment(frameOffset: Int) {
        let codonTable = TranslationCodonTable(rawValue: translationCodonTable) ?? .standard
        mafftActions?.alignAminoAcidGuidedNucleotide(frameOffset, codonTable)
    }

    @MainActor
    private func presentOperationError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = AppStrings.operationFailed
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: AppStrings.ok)
        alert.runModal()
    }
}
