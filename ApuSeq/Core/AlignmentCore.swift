import Foundation

struct AlignmentData {
    let format: AlignmentFormat
    let rows: [AlignmentRow]
    let length: Int
    let sequenceKind: SequenceKind

    static let empty = AlignmentData(format: .plainText, rows: [], length: 0, sequenceKind: .nucleotide)
}

struct AlignmentRow {
    let name: String
    let sequence: String
}

enum SequenceKind: String {
    case nucleotide = "Nucleotide"
    case aminoAcid = "Amino acid"
}

enum AlignmentFormat: String {
    case fasta = "FASTA"
    case clustal = "CLUSTAL"
    case plainText = "Plain Text"
}

enum AlignmentParseError: LocalizedError {
    case unsupportedFormat

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "Input data is not in FASTA, CLUSTAL, or plain-text sequence format."
        }
    }
}

enum AlignmentParser {
    static func parse(_ text: String) throws -> AlignmentData {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return .empty }

        if normalized.hasPrefix(">") {
            return try parseFASTA(normalized)
        }
        if normalized.uppercased().hasPrefix("CLUSTAL") {
            return try parseCLUSTAL(normalized)
        }
        return try parsePlainText(normalized)
    }

    private static func parseFASTA(_ text: String) throws -> AlignmentData {
        let lines = text.components(separatedBy: .newlines)
        var rows: [AlignmentRow] = []
        var currentName: String?
        var currentSequenceParts: [String] = []

        func commitCurrent() {
            guard let currentName else { return }
            let sequence = currentSequenceParts.joined()
            rows.append(AlignmentRow(name: currentName, sequence: sequence))
        }

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if line.hasPrefix(">") {
                commitCurrent()
                let title = String(line.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
                currentName = title.isEmpty ? "Unnamed Sequence" : title
                currentSequenceParts = []
            } else {
                let cleaned = line.replacingOccurrences(of: " ", with: "")
                currentSequenceParts.append(cleaned)
            }
        }

        commitCurrent()
        guard !rows.isEmpty else { throw AlignmentParseError.unsupportedFormat }
        return normalize(rows: rows, format: .fasta)
    }

    private static func parseCLUSTAL(_ text: String) throws -> AlignmentData {
        let lines = text.components(separatedBy: .newlines)
        var order: [String] = []
        var sequencesByName: [String: String] = [:]

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if line.uppercased().hasPrefix("CLUSTAL") || line.uppercased().hasPrefix("MUSCLE") {
                continue
            }
            if let first = line.first, first == "*" || first == ":" || first == "." {
                continue
            }

            let columns = line.split(whereSeparator: \.isWhitespace)
            guard columns.count >= 2 else { continue }
            let name = String(columns[0])
            let chunk = String(columns[1])

            if sequencesByName[name] == nil {
                order.append(name)
                sequencesByName[name] = ""
            }
            sequencesByName[name, default: ""] += chunk
        }

        let rows = order.map { AlignmentRow(name: $0, sequence: sequencesByName[$0, default: ""]) }
        guard !rows.isEmpty else { throw AlignmentParseError.unsupportedFormat }
        return normalize(rows: rows, format: .clustal)
    }

    private static func parsePlainText(_ text: String) throws -> AlignmentData {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let rows = lines.enumerated().map { index, line in
            AlignmentRow(
                name: "Sequence \(index + 1)",
                sequence: line.replacingOccurrences(of: " ", with: "")
            )
        }

        guard !rows.isEmpty else { throw AlignmentParseError.unsupportedFormat }
        return normalize(rows: rows, format: .plainText)
    }

    private static func normalize(rows: [AlignmentRow], format: AlignmentFormat) -> AlignmentData {
        let maxLength = rows.map(\.sequence.count).max() ?? 0
        let normalizedRows = rows.enumerated().map { index, row in
            let cleanName = row.name.isEmpty ? "Sequence \(index + 1)" : row.name
            let paddingCount = maxLength - row.sequence.count
            let padding = String(repeating: "-", count: max(paddingCount, 0))
            return AlignmentRow(name: cleanName, sequence: row.sequence + padding)
        }
        return AlignmentData(
            format: format,
            rows: normalizedRows,
            length: maxLength,
            sequenceKind: inferSequenceKind(from: normalizedRows)
        )
    }

    private static func inferSequenceKind(from rows: [AlignmentRow]) -> SequenceKind {
        let nucleotideSet = Set("ACGTUNRYSWKMBDHV")
        for row in rows {
            for scalar in row.sequence.unicodeScalars {
                let residue = Character(String(scalar)).uppercased().first ?? Character(String(scalar))
                if residue == "-" || residue == "." || residue == "?" { continue }
                if !nucleotideSet.contains(residue) {
                    return .aminoAcid
                }
            }
        }
        return .nucleotide
    }
}
