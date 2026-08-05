import Foundation

enum AppStrings {
    static let addSequence = String(localized: "Add Sequence...")
    static let alignment = String(localized: "Alignment")
    static let copyConsensus = String(localized: "Copy Consensus")
    static let copySequence = String(localized: "Copy Sequence")
    static let copyCurrentSequence = String(localized: "Copy Current Sequence")
    static let copyAsFASTA = String(localized: "Copy as FASTA")
    static let copyCurrentSequenceAsFASTA = String(localized: "Copy Current Sequence as FASTA")
    static let copySelectionAsFASTA = String(localized: "Copy Selection as FASTA")
    static let addSequenceTitle = String(localized: "Add Sequence")
    static let addFASTAFromClipboard = String(localized: "Add FASTA from Clipboard")
    static let findSequenceName = String(localized: "Find Sequence Name...")
    static let findSequenceNameTitle = String(localized: "Find Sequence Name")
    static let sequenceNameNotFound = String(localized: "Sequence name not found.")
    static let renameSequence = String(localized: "Rename Sequence...")
    static let renameSequenceTitle = String(localized: "Rename Sequence")
    static let deleteSequence = String(localized: "Delete Sequence")
    static let insertGapColumn = String(localized: "Insert Gap Column")
    static let removeAllGapColumns = String(localized: "Remove All-Gap Columns")
    static let trimTrailingGaps = String(localized: "Trim Trailing Gaps")
    static let sortSequences = String(localized: "Sort Sequences")
    static let sortSequencesByName = String(localized: "By Name")
    static let sortSequencesByUPGMA = String(localized: "By UPGMA")
    static let select = String(localized: "Select")
    static let selectLine = String(localized: "Select Line")
    static let selectUngappedChunk = String(localized: "Select Ungapped Chunk")
    static let enterEditMode = String(localized: "Enter Edit Mode")
    static let exitEditMode = String(localized: "Exit Edit Mode")
    static let editModeAutosaveWarningTitle = String(localized: "Changes in Edit mode are autosaved with versions.")
    static let editModeAutosaveWarningMessage = String(localized: "Editing can modify the file. Use File > Revert To to restore an earlier version when available.")
    static let alignWithMAFFT = String(localized: "Align with MAFFT")
    static let alignEntireAlignment = String(localized: "Entire Alignment")
    static let alignWithMAFFTAuto = String(localized: "Align with MAFFT Auto")
    static let alignSelectedColumns = String(localized: "Selected Columns")
    static let alignSelectedColumnsWithMAFFTAuto = String(localized: "Align Selected Columns with MAFFT Auto")
    static let aligningWithMAFFT = String(localized: "Aligning with MAFFT...")
    static let mafftAlignmentFailed = String(localized: "MAFFT Alignment Failed")
    static let openSourceLicenses = String(localized: "Open Source Licenses")
    static let openSourceLicensesMenuItem = String(localized: "Open Source Licenses...")
    static let reverseComplement = String(localized: "Reverse Complement")
    static let website = String(localized: "Website")
    static let cancel = String(localized: "Cancel")
    static let ok = String(localized: "OK")
    static let sequenceMenu = String(localized: "Sequence")
    static let referenceMenu = String(localized: "Reference")
    static let setAsReference = String(localized: "Set as Reference")
    static let setCurrentSequenceAsReference = String(localized: "Set Current Sequence as Reference")
    static let clearReference = String(localized: "Clear Reference")

    static func appearanceName(_ mode: AppAppearanceMode) -> String {
        switch mode {
        case .system:
            return String(localized: "System")
        case .light:
            return String(localized: "Light")
        case .dark:
            return String(localized: "Dark")
        }
    }

    static func backgroundName(_ mode: AlignmentBackgroundMode) -> String {
        switch mode {
        case .none:
            return String(localized: "None")
        case .residue:
            return String(localized: "Residue")
        case .minority:
            return String(localized: "Minority")
        case .reference:
            return String(localized: "Reference")
        case .identity:
            return String(localized: "Identity")
        }
    }

    static func displayOrderName(_ mode: AlignmentDisplayOrderMode) -> String {
        switch mode {
        case .original:
            return String(localized: "Original")
        case .name:
            return String(localized: "Name")
        case .upgma:
            return String(localized: "UPGMA")
        }
    }

    static func alignmentFormatName(_ format: AlignmentFormat) -> String {
        switch format {
        case .fasta:
            return String(localized: "FASTA")
        case .clustal:
            return String(localized: "CLUSTAL")
        case .plainText:
            return String(localized: "Plain Text")
        }
    }
}
