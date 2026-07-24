import AppKit
import SwiftUI

struct SequenceTransformContext {
    let rawText: String
    let sequenceKind: SequenceKind
}

struct AlignmentEditActions {
    let canAddSequence: Bool
    let addSequence: () -> Void
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
}

struct ViewerModeActions {
    let toggleTitle: String
    let toggle: () -> Void
}

struct AlignmentDisplayActions {
    let backgroundMode: AlignmentBackgroundMode
    let setBackgroundMode: (AlignmentBackgroundMode) -> Void
    let displayOrderMode: AlignmentDisplayOrderMode
    let canChangeDisplayOrder: Bool
    let canDisplayUPGMAOrder: Bool
    let setDisplayOrderMode: (AlignmentDisplayOrderMode) -> Void
}

struct MAFFTAlignmentActions {
    let canAlign: Bool
    let align: () -> Void
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

struct FindCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .pasteboard) {
            Divider()
            Button(String(localized: "Find")) {
                FindActionDispatcher.perform(.showFindInterface)
            }
            .keyboardShortcut("f", modifiers: .command)

            Button(String(localized: "Find Next")) {
                FindActionDispatcher.perform(.nextMatch)
            }
            .keyboardShortcut("g", modifiers: .command)

            Button(String(localized: "Find Previous")) {
                FindActionDispatcher.perform(.previousMatch)
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])
        }
    }
}

struct ColumnSelectionCommands: Commands {
    @FocusedValue(\.alignmentCopyActions) private var actions

    var body: some Commands {
        CommandGroup(after: .pasteboard) {
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

struct AlignmentEditCommands: Commands {
    @FocusedValue(\.alignmentEditActions) private var actions

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Button(AppStrings.addSequence) {
                actions?.addSequence()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(actions?.canAddSequence != true)
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
    @AppStorage("showReferencePanel") private var showReferencePanel = false
    @AppStorage("showConsensusPanel") private var showConsensusPanel = false
    @AppStorage("showConservationPanel") private var showConservationPanel = false
    @FocusedValue(\.alignmentDisplayActions) private var displayActions

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Divider()
            Button(showReferencePanel ? String(localized: "Hide Reference Panel") : String(localized: "Show Reference Panel")) {
                showReferencePanel.toggle()
            }
            Button(showConsensusPanel ? String(localized: "Hide Consensus Panel") : String(localized: "Show Consensus Panel")) {
                showConsensusPanel.toggle()
            }
            Button(showConservationPanel ? String(localized: "Hide Identity Panel") : String(localized: "Show Identity Panel")) {
                showConservationPanel.toggle()
            }

            Divider()
            Picker(String(localized: "Background Color"), selection: backgroundModeBinding) {
                ForEach(AlignmentBackgroundMode.allCases) { mode in
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

private enum FindActionDispatcher {
    static func perform(_ action: NSTextFinder.Action) {
        let item = NSMenuItem()
        item.tag = action.rawValue
        NSApp.sendAction(#selector(NSResponder.performTextFinderAction(_:)), to: nil, from: item)
    }
}

struct AlignmentCommands: Commands {
    @FocusedValue(\.alignmentEditActions) private var editActions
    @FocusedValue(\.mafftAlignmentActions) private var mafftActions
    @FocusedValue(\.sequenceTransformContext) private var context
    @Environment(\.newDocument) private var newDocument
    @AppStorage("translationCodonTable") private var translationCodonTable = TranslationCodonTable.standard.rawValue

    var body: some Commands {
        CommandMenu(AppStrings.alignment) {
            Button(AppStrings.alignWithMAFFTAuto) {
                mafftActions?.align()
            }
            .disabled(mafftActions?.canAlign != true)

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

            Divider()

            Button(AppStrings.reverseComplement) {
                runReverseComplement()
            }
            .disabled(!canReverseComplement)

            Menu(String(localized: "Translation")) {
                Button(String(localized: "Frame +0")) { runTranslation(frameOffset: 0) }
                    .keyboardShortcut("0", modifiers: [.command, .option])
                Button(String(localized: "Frame +1")) { runTranslation(frameOffset: 1) }
                Button(String(localized: "Frame +2")) { runTranslation(frameOffset: 2) }
            }
            .disabled(!canTranslate)
        }
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
                        ApuSeqDocument(
                            rawText: reverseComplemented,
                            markEditedOnFirstDisplay: true
                        )
                    }
                }
            } catch {
                NSSound.beep()
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
                        ApuSeqDocument(
                            rawText: translated,
                            markEditedOnFirstDisplay: true
                        )
                    }
                }
            } catch {
                NSSound.beep()
            }
        }
    }
}
