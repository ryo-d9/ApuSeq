import Foundation

enum TranslationCodonTable: String, CaseIterable, Identifiable {
    case standard
    case vertebrateMitochondrial

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard:
            return "Standard"
        case .vertebrateMitochondrial:
            return "Vertebrate Mitochondrial"
        }
    }
}

enum AlignmentTranslationError: LocalizedError {
    case unsupportedSequenceKind

    var errorDescription: String? {
        switch self {
        case .unsupportedSequenceKind:
            return "Translation is available only for nucleotide alignments."
        }
    }
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
            lines.append(">\(row.name)")
            lines.append(translateSequence(row.sequence, frameOffset: frameOffset, codonTable: codonTable))
        }
        return lines.joined(separator: "\n")
    }

    private static func translateSequence(_ sequence: String, frameOffset: Int, codonTable: TranslationCodonTable) -> String {
        let normalized = sequence.uppercased().map { char -> Character in
            if char == "U" { return "T" }
            return char
        }
        let residues = normalized.filter { $0 != "-" && $0 != "." && !$0.isWhitespace }
        guard frameOffset < residues.count else { return "" }

        let chars = Array(residues)
        let mapping = codonMapping(codonTable)
        var aminoAcids = String()
        aminoAcids.reserveCapacity(max((chars.count - frameOffset) / 3, 0))

        var index = frameOffset
        while index + 2 < chars.count {
            let codon = String([chars[index], chars[index + 1], chars[index + 2]])
            aminoAcids.append(mapping[codon] ?? "X")
            index += 3
        }
        return aminoAcids
    }

    private static func codonMapping(_ table: TranslationCodonTable) -> [String: Character] {
        switch table {
        case .standard:
            return standardTable
        case .vertebrateMitochondrial:
            var table = standardTable
            table["AGA"] = "*"
            table["AGG"] = "*"
            table["ATA"] = "M"
            table["TGA"] = "W"
            return table
        }
    }

    private static let standardTable: [String: Character] = [
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
