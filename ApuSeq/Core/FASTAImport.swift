import Foundation

nonisolated enum FASTAImportMode: Sendable {
    case unchanged
    case reverseComplemented
}

nonisolated enum FASTAImportError: LocalizedError {
    case emptySelection
    case incompatibleSequenceKind
    case reverseComplementRequiresNucleotides

    var errorDescription: String? {
        switch self {
        case .emptySelection:
            return String(localized: "No FASTA sequences were found.")
        case .incompatibleSequenceKind:
            return String(localized: "The imported sequences do not match the sequence type of the current document.")
        case .reverseComplementRequiresNucleotides:
            return String(localized: "Reverse complement is available only for nucleotide sequences.")
        }
    }
}

nonisolated enum FASTAImporter {
    nonisolated static func rows(
        from fileContents: [String],
        mode: FASTAImportMode,
        existingSequenceKind: SequenceKind?
    ) throws -> [AlignmentRow] {
        var importedRows: [AlignmentRow] = []
        var importedSequenceKind = existingSequenceKind

        for content in fileContents {
            try Task.checkCancellation()
            let rows = try AlignmentParser.parseFASTARows(content)
            let sequenceKind = AlignmentParser.normalize(rows: rows, format: .fasta).sequenceKind

            if let importedSequenceKind, sequenceKind != importedSequenceKind {
                throw FASTAImportError.incompatibleSequenceKind
            }
            if mode == .reverseComplemented, sequenceKind != .nucleotide {
                throw FASTAImportError.reverseComplementRequiresNucleotides
            }

            importedRows.reserveCapacity(importedRows.count + rows.count)
            for row in rows {
                try Task.checkCancellation()
                let sequence = mode == .reverseComplemented
                    ? AlignmentReverseComplementer.reverseComplement(row.sequence)
                    : row.sequence
                importedRows.append(AlignmentRow(name: row.name, sequence: sequence))
            }
            importedSequenceKind = sequenceKind
        }

        guard !importedRows.isEmpty else {
            throw FASTAImportError.emptySelection
        }

        return importedRows
    }
}
