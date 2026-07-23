import Foundation

enum AppStrings {
    static let addSequence = String(localized: "Add Sequence...")
    static let alignment = String(localized: "Alignment")
    static let copyConsensus = String(localized: "Copy Consensus")
    static let copySequence = String(localized: "Copy Sequence")
    static let addSequenceTitle = String(localized: "Add Sequence")
    static let renameSequence = String(localized: "Rename Sequence...")
    static let renameSequenceTitle = String(localized: "Rename Sequence")
    static let deleteSequence = String(localized: "Delete Sequence")
    static let removeAllGapColumns = String(localized: "Remove All-Gap Columns")
    static let select = String(localized: "Select")
    static let selectLine = String(localized: "Select Line")
    static let selectUngappedChunk = String(localized: "Select Ungapped Chunk")
    static let enterEditMode = String(localized: "Enter Edit Mode")
    static let exitEditMode = String(localized: "Exit Edit Mode")
    static let alignWithMAFFTAuto = String(localized: "Align with MAFFT Auto")
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
        case .different:
            return String(localized: "Different")
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
