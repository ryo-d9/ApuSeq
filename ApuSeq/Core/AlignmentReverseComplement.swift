import Foundation

enum AlignmentReverseComplementError: LocalizedError {
    case unsupportedSequenceKind

    var errorDescription: String? {
        switch self {
        case .unsupportedSequenceKind:
            return String(localized: "Reverse complement is available only for nucleotide alignments.")
        }
    }
}

enum AlignmentReverseComplementer {
    static func reverseComplementFASTA(rawText: String) throws -> String {
        let alignment = try AlignmentParser.parse(rawText)
        guard alignment.sequenceKind == .nucleotide else {
            throw AlignmentReverseComplementError.unsupportedSequenceKind
        }

        var lines: [String] = []
        lines.reserveCapacity(alignment.rows.count * 2)
        for row in alignment.rows {
            lines.append(">\(row.name)")
            lines.append(reverseComplement(row.sequence))
        }
        return lines.joined(separator: "\n")
    }

    private static func reverseComplement(_ sequence: String) -> String {
        var output = String()
        output.reserveCapacity(sequence.count)
        for scalar in sequence.unicodeScalars.reversed() {
            output.unicodeScalars.append(complement(scalar))
        }
        return output
    }

    private static func complement(_ scalar: UnicodeScalar) -> UnicodeScalar {
        switch scalar.value {
        case 65: return "T" // A
        case 84, 85: return "A" // T, U
        case 67: return "G" // C
        case 71: return "C" // G
        case 82: return "Y" // R
        case 89: return "R" // Y
        case 75: return "M" // K
        case 77: return "K" // M
        case 83: return "S" // S
        case 87: return "W" // W
        case 66: return "V" // B
        case 86: return "B" // V
        case 68: return "H" // D
        case 72: return "D" // H
        case 78: return "N" // N
        case 97: return "t" // a
        case 116, 117: return "a" // t, u
        case 99: return "g" // c
        case 103: return "c" // g
        case 114: return "y" // r
        case 121: return "r" // y
        case 107: return "m" // k
        case 109: return "k" // m
        case 115: return "s" // s
        case 119: return "w" // w
        case 98: return "v" // b
        case 118: return "b" // v
        case 100: return "h" // d
        case 104: return "d" // h
        case 110: return "n" // n
        default: return scalar
        }
    }
}
