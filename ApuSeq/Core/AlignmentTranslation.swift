import Foundation

enum TranslationCodonTable: String, CaseIterable, Identifiable {
    case standard
    case vertebrateMitochondrial
    case yeastMitochondrial
    case moldProtozoanMitochondrial
    case invertebrateMitochondrial
    case bacterialArchaealPlastid

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard:
            return String(localized: "Standard")
        case .vertebrateMitochondrial:
            return String(localized: "Vertebrate Mitochondrial")
        case .yeastMitochondrial:
            return String(localized: "Yeast Mitochondrial")
        case .moldProtozoanMitochondrial:
            return String(localized: "Mold/Protozoan Mitochondrial")
        case .invertebrateMitochondrial:
            return String(localized: "Invertebrate Mitochondrial")
        case .bacterialArchaealPlastid:
            return String(localized: "Bacterial/Archaeal/Plastid")
        }
    }
}

enum AlignmentTranslationError: LocalizedError {
    case unsupportedSequenceKind
    case incompleteCodon(sequenceName: String)

    var errorDescription: String? {
        switch self {
        case .unsupportedSequenceKind:
            return String(localized: "Translation is available only for nucleotide alignments.")
        case .incompleteCodon(let sequenceName):
            return String(localized: "Sequence \"\(sequenceName)\" does not contain complete codons in the selected frame.")
        }
    }
}

struct CodingSequenceTranslation: Equatable, Sendable {
    let aminoAcids: String
    let codons: [String]
}

enum AlignmentTranslator {
    static func translateFASTA(rawText: String, frameOffset: Int, codonTable: TranslationCodonTable) throws -> String {
        let alignment = try AlignmentParser.parse(rawText)
        guard alignment.sequenceKind == .nucleotide else {
            throw AlignmentTranslationError.unsupportedSequenceKind
        }

        var lines: [String] = []
        lines.reserveCapacity(alignment.rows.count * 2)
        for row in alignment.rows {
            let translated = try translatedCodingSequence(
                row.sequence,
                sequenceName: row.name,
                frameOffset: frameOffset,
                codonTable: codonTable,
                requiresCompleteCodons: false
            )
            lines.append(">\(row.name)")
            lines.append(translated.aminoAcids)
        }
        return lines.joined(separator: "\n")
    }

    nonisolated static func translatedCodingSequence(
        _ sequence: String,
        sequenceName: String,
        frameOffset: Int,
        codonTable: TranslationCodonTable,
        requiresCompleteCodons: Bool
    ) throws -> CodingSequenceTranslation {
        let normalized = sequence.uppercased().map { char -> Character in
            if char == "U" { return "T" }
            return char
        }
        let residues = normalized.filter { $0 != "-" && $0 != "." && !$0.isWhitespace }
        guard frameOffset < residues.count else {
            return CodingSequenceTranslation(aminoAcids: "", codons: [])
        }
        if requiresCompleteCodons && (residues.count - frameOffset) % 3 != 0 {
            throw AlignmentTranslationError.incompleteCodon(sequenceName: sequenceName)
        }

        let chars = Array(residues)
        let mapping = codonMapping(codonTable)
        var aminoAcids = String()
        aminoAcids.reserveCapacity(max((chars.count - frameOffset) / 3, 0))
        var codons: [String] = []
        codons.reserveCapacity(max((chars.count - frameOffset) / 3, 0))

        var index = frameOffset
        while index + 2 < chars.count {
            let codon = String([chars[index], chars[index + 1], chars[index + 2]])
            codons.append(codon)
            aminoAcids.append(mapping[codon] ?? "X")
            index += 3
        }
        return CodingSequenceTranslation(aminoAcids: aminoAcids, codons: codons)
    }

    nonisolated private static func codonMapping(_ table: TranslationCodonTable) -> [String: Character] {
        switch table {
        case .standard, .bacterialArchaealPlastid:
            return standardTable
        case .vertebrateMitochondrial:
            var table = standardTable
            table["AGA"] = "*"
            table["AGG"] = "*"
            table["ATA"] = "M"
            table["TGA"] = "W"
            return table
        case .yeastMitochondrial:
            var table = standardTable
            table["ATA"] = "M"
            table["TGA"] = "W"
            table["CTT"] = "T"
            table["CTC"] = "T"
            table["CTA"] = "T"
            table["CTG"] = "T"
            return table
        case .moldProtozoanMitochondrial:
            var table = standardTable
            table["TGA"] = "W"
            return table
        case .invertebrateMitochondrial:
            var table = standardTable
            table["AGA"] = "S"
            table["AGG"] = "S"
            table["ATA"] = "M"
            table["TGA"] = "W"
            return table
        }
    }

    nonisolated private static let standardTable: [String: Character] = [
        "TTT": "F", "TTC": "F", "TTA": "L", "TTG": "L",
        "TCT": "S", "TCC": "S", "TCA": "S", "TCG": "S",
        "TAT": "Y", "TAC": "Y", "TAA": "*", "TAG": "*",
        "TGT": "C", "TGC": "C", "TGA": "*", "TGG": "W",
        "CTT": "L", "CTC": "L", "CTA": "L", "CTG": "L",
        "CCT": "P", "CCC": "P", "CCA": "P", "CCG": "P",
        "CAT": "H", "CAC": "H", "CAA": "Q", "CAG": "Q",
        "CGT": "R", "CGC": "R", "CGA": "R", "CGG": "R",
        "ATT": "I", "ATC": "I", "ATA": "I", "ATG": "M",
        "ACT": "T", "ACC": "T", "ACA": "T", "ACG": "T",
        "AAT": "N", "AAC": "N", "AAA": "K", "AAG": "K",
        "AGT": "S", "AGC": "S", "AGA": "R", "AGG": "R",
        "GTT": "V", "GTC": "V", "GTA": "V", "GTG": "V",
        "GCT": "A", "GCC": "A", "GCA": "A", "GCG": "A",
        "GAT": "D", "GAC": "D", "GAA": "E", "GAG": "E",
        "GGT": "G", "GGC": "G", "GGA": "G", "GGG": "G"
    ]
}

enum AminoAcidGuidedNucleotideAlignmentError: LocalizedError {
    case unsupportedFormat
    case unsupportedSequenceKind
    case insufficientSequences
    case emptyTranslation(sequenceName: String)
    case alignedSequenceCountMismatch
    case codonMappingFailed(sequenceName: String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return String(localized: "Codon alignment requires FASTA input.")
        case .unsupportedSequenceKind:
            return String(localized: "Codon alignment is available only for nucleotide sequences.")
        case .insufficientSequences:
            return String(localized: "At least two coding sequences are required for codon alignment.")
        case .emptyTranslation(let sequenceName):
            return String(localized: "Sequence \"\(sequenceName)\" does not contain a translated coding region in the selected frame.")
        case .alignedSequenceCountMismatch:
            return String(localized: "The amino acid alignment result did not match the input sequences.")
        case .codonMappingFailed(let sequenceName):
            return String(localized: "Could not map the aligned amino acid sequence back to codons for \"\(sequenceName)\".")
        }
    }
}

enum AminoAcidGuidedNucleotideAligner {
    nonisolated static func align(
        rawText: String,
        frameOffset: Int,
        codonTable: TranslationCodonTable
    ) async throws -> String {
        let alignment = try AlignmentParser.parse(rawText)
        guard alignment.format == .fasta else {
            throw AminoAcidGuidedNucleotideAlignmentError.unsupportedFormat
        }
        guard alignment.sequenceKind == .nucleotide else {
            throw AminoAcidGuidedNucleotideAlignmentError.unsupportedSequenceKind
        }
        guard alignment.rows.count >= 2 else {
            throw AminoAcidGuidedNucleotideAlignmentError.insufficientSequences
        }

        let translations = try alignment.rows.map { row in
            try AlignmentTranslator.translatedCodingSequence(
                row.sequence,
                sequenceName: row.name,
                frameOffset: frameOffset,
                codonTable: codonTable,
                requiresCompleteCodons: true
            )
        }
        for (row, translation) in zip(alignment.rows, translations) where translation.aminoAcids.isEmpty {
            throw AminoAcidGuidedNucleotideAlignmentError.emptyTranslation(sequenceName: row.name)
        }
        let aminoAcidRows = zip(alignment.rows, translations).map { row, translation in
            AlignmentRow(name: row.name, sequence: mafftCompatibleAminoAcidSequence(translation.aminoAcids))
        }
        let alignedAminoAcidRows = try await MAFFTAligner.alignAuto(rows: aminoAcidRows)
        guard alignedAminoAcidRows.count == translations.count else {
            throw AminoAcidGuidedNucleotideAlignmentError.alignedSequenceCountMismatch
        }
        let nucleotideRows = try alignedAminoAcidRows.enumerated().map { index, alignedRow in
            let codonSequence = try backMapCodons(
                alignedAminoAcidSequence: alignedRow.sequence,
                codons: translations[index].codons,
                sequenceName: alignedRow.name
            )
            return AlignmentRow(name: alignment.rows[index].name, sequence: codonSequence)
        }
        return AlignmentSerializer.serialize(rows: nucleotideRows, preferredFormat: .fasta)
    }

    nonisolated static func backMapCodons(
        alignedAminoAcidSequence: String,
        codons: [String],
        sequenceName: String
    ) throws -> String {
        var output = String()
        output.reserveCapacity(alignedAminoAcidSequence.count * 3)
        var codonIndex = 0

        for residue in alignedAminoAcidSequence {
            if residue == "-" || residue == "." {
                output += "---"
                continue
            }
            guard codonIndex < codons.count else {
                throw AminoAcidGuidedNucleotideAlignmentError.codonMappingFailed(sequenceName: sequenceName)
            }
            output += codons[codonIndex]
            codonIndex += 1
        }

        guard codonIndex == codons.count else {
            throw AminoAcidGuidedNucleotideAlignmentError.codonMappingFailed(sequenceName: sequenceName)
        }
        return output
    }

    nonisolated private static func mafftCompatibleAminoAcidSequence(_ sequence: String) -> String {
        sequence.replacingOccurrences(of: "*", with: "X")
    }
}
