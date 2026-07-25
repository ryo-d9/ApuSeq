import Foundation

nonisolated struct AlignmentData: Sendable {
    let format: AlignmentFormat
    let rows: [AlignmentRow]
    let length: Int
    let sequenceKind: SequenceKind

    nonisolated static let empty = AlignmentData(format: .plainText, rows: [], length: 0, sequenceKind: .nucleotide)
}

nonisolated struct AlignmentRow: Equatable, Sendable {
    nonisolated let name: String
    nonisolated let sequence: String
}

enum SequenceKind: String, Sendable {
    case nucleotide = "Nucleotide"
    case aminoAcid = "Amino acid"
}

enum AlignmentFormat: String, Sendable {
    case fasta = "FASTA"
    case clustal = "CLUSTAL"
    case plainText = "Plain Text"
}

enum AlignmentParseError: LocalizedError {
    case unsupportedFormat

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return String(localized: "Input data is not in FASTA, CLUSTAL, or plain-text sequence format.")
        }
    }
}

enum AlignmentParser {
    nonisolated static func parse(_ text: String) throws -> AlignmentData {
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

    nonisolated private static func parseFASTA(_ text: String) throws -> AlignmentData {
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

    nonisolated private static func parseCLUSTAL(_ text: String) throws -> AlignmentData {
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

    nonisolated private static func parsePlainText(_ text: String) throws -> AlignmentData {
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

    nonisolated private static func normalize(rows: [AlignmentRow], format: AlignmentFormat) -> AlignmentData {
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

    nonisolated private static func inferSequenceKind(from rows: [AlignmentRow]) -> SequenceKind {
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

enum AlignmentSerializer {
    nonisolated private static let clustalBlockWidth = 60
    nonisolated private static let clustalNamePadding = 4

    nonisolated static func serialize(rows: [AlignmentRow], preferredFormat: AlignmentFormat) -> String {
        switch preferredFormat {
        case .clustal:
            return serializeCLUSTAL(rows: rows)
        case .fasta, .plainText:
            return serializeFASTA(rows: rows)
        }
    }

    nonisolated private static func serializeFASTA(rows: [AlignmentRow]) -> String {
        var output = ""
        let sequenceLength = rows.reduce(0) { $0 + $1.sequence.count }
        output.reserveCapacity(sequenceLength + (rows.count * 16))

        for row in rows {
            output += ">"
            output += row.name
            output += "\n"
            output += row.sequence
            output += "\n"
        }
        return output
    }

    nonisolated private static func serializeCLUSTAL(rows: [AlignmentRow]) -> String {
        guard !rows.isEmpty else { return "CLUSTAL\n" }

        let serializedRows = rows.map {
            AlignmentRow(name: sanitizedCLUSTALName($0.name), sequence: $0.sequence)
        }
        let alignmentLength = serializedRows.map(\.sequence.count).max() ?? 0
        let nameColumnWidth = (serializedRows.map { $0.name.count }.max() ?? 0) + clustalNamePadding

        var output = "CLUSTAL\n\n"
        for blockStart in stride(from: 0, to: max(alignmentLength, 1), by: clustalBlockWidth) {
            let blockEnd = min(blockStart + clustalBlockWidth, alignmentLength)
            for row in serializedRows {
                let chunk = sequenceChunk(row.sequence, start: blockStart, end: blockEnd)
                output += row.name.padding(toLength: nameColumnWidth, withPad: " ", startingAt: 0)
                output += chunk
                output += "\n"
            }
            output += "\n"
        }
        return output
    }

    nonisolated private static func sequenceChunk(_ sequence: String, start: Int, end: Int) -> String {
        guard start < end else { return "" }
        let source = sequence as NSString
        guard start < source.length else { return "" }
        let length = max(min(end, source.length) - start, 0)
        return source.substring(with: NSRange(location: start, length: length))
    }

    nonisolated private static func sanitizedCLUSTALName(_ name: String) -> String {
        let sanitized = name.map { character in
            character.isWhitespace ? "_" : character
        }
        let output = String(sanitized)
        return output.isEmpty ? "Sequence" : output
    }
}

enum AlignmentColumnEditor {
    struct RowEdit: Sendable {
        let row: Int
        let column: Int
        let length: Int
        let replacement: String

        init(row: Int, column: Int, length: Int, replacement: String) {
            self.row = row
            self.column = column
            self.length = length
            self.replacement = replacement
        }
    }

    nonisolated static func hasTrailingGaps(in rows: [AlignmentRow]) -> Bool {
        rows.contains { row in
            guard let last = row.sequence.unicodeScalars.last else { return false }
            return isGap(last)
        }
    }

    nonisolated static func trimmingTrailingGaps(from rows: [AlignmentRow]) -> [AlignmentRow]? {
        var didTrim = false
        let trimmedRows = rows.map { row in
            let trimmedSequence = trimmingTrailingGaps(in: row.sequence)
            if trimmedSequence != row.sequence {
                didTrim = true
            }
            return AlignmentRow(name: row.name, sequence: trimmedSequence)
        }
        return didTrim ? trimmedRows : nil
    }

    nonisolated static func replacingRowsOnly(in sequences: [String], edits: [RowEdit]) -> (sequences: [String], length: Int)? {
        guard !sequences.isEmpty, !edits.isEmpty else { return nil }

        var editedSequences = sequences
        let editsByRow = Dictionary(grouping: edits) { $0.row }
        for (row, rowEdits) in editsByRow {
            guard editedSequences.indices.contains(row) else { continue }
            let sortedEdits = rowEdits.sorted {
                if $0.column == $1.column { return $0.length > $1.length }
                return $0.column > $1.column
            }
            for edit in sortedEdits {
                replaceCharacters(
                    in: &editedSequences[row],
                    column: edit.column,
                    length: edit.length,
                    with: edit.replacement
                )
            }
        }

        let maxLength = editedSequences.map { ($0 as NSString).length }.max() ?? 0
        let paddedSequences = editedSequences.map { sequence in
            let paddingCount = maxLength - (sequence as NSString).length
            return sequence + String(repeating: "-", count: max(paddingCount, 0))
        }
        return (paddedSequences, maxLength)
    }

    nonisolated static func insertingGapColumn(in rows: [AlignmentRow], column: Int) -> [AlignmentRow]? {
        guard !rows.isEmpty else { return nil }
        let maxLength = rows.map { ($0.sequence as NSString).length }.max() ?? 0
        guard column >= 0, column <= maxLength else { return nil }

        return rows.map { row in
            var sequence = row.sequence
            let paddingCount = maxLength - (sequence as NSString).length
            if paddingCount > 0 {
                sequence += String(repeating: "-", count: paddingCount)
            }
            insertCharacters("-", in: &sequence, column: column)
            return AlignmentRow(name: row.name, sequence: sequence)
        }
    }

    nonisolated static func removingAllGapColumns(from rows: [AlignmentRow], length: Int) -> [AlignmentRow]? {
        guard let keepColumns = removableAllGapColumnMask(rows: rows, length: length) else { return nil }
        let keptColumnCount = keepColumns.filter(\.self).count
        return rows.map { row in
            AlignmentRow(
                name: row.name,
                sequence: sequence(row.sequence, keepingColumns: keepColumns, keptColumnCount: keptColumnCount)
            )
        }
    }

    nonisolated private static func removableAllGapColumnMask(rows: [AlignmentRow], length: Int) -> [Bool]? {
        guard !rows.isEmpty, length > 0 else { return nil }

        let sequences = rows.map { $0.sequence as NSString }
        var keepColumns = Array(repeating: true, count: length)
        var removedCount = 0

        for column in 0..<length {
            let isAllGap = sequences.allSatisfy { sequence in
                guard column < sequence.length else { return true }
                return isGap(sequence.character(at: column))
            }
            if isAllGap {
                keepColumns[column] = false
                removedCount += 1
            }
        }

        guard removedCount > 0, removedCount < length else { return nil }
        return keepColumns
    }

    nonisolated private static func sequence(_ sequence: String, keepingColumns keepColumns: [Bool], keptColumnCount: Int) -> String {
        let source = sequence as NSString
        var result = ""
        result.reserveCapacity(keptColumnCount)
        for (column, shouldKeep) in keepColumns.enumerated() where shouldKeep {
            guard column < source.length else { continue }
            result += source.substring(with: NSRange(location: column, length: 1))
        }
        return result
    }

    nonisolated private static func trimmingTrailingGaps(in sequence: String) -> String {
        let scalars = sequence.unicodeScalars
        var endIndex = scalars.endIndex
        while endIndex > scalars.startIndex {
            let previousIndex = scalars.index(before: endIndex)
            guard isGap(scalars[previousIndex]) else { break }
            endIndex = previousIndex
        }
        return String(scalars[..<endIndex])
    }

    nonisolated private static func replaceCharacters(in sequence: inout String, column: Int, length: Int, with replacement: String) {
        let source = sequence as NSString
        let start = min(max(column, 0), source.length)
        let safeLength = min(max(length, 0), source.length - start)
        sequence = source.replacingCharacters(in: NSRange(location: start, length: safeLength), with: replacement)
    }

    nonisolated private static func insertCharacters(_ insertion: String, in sequence: inout String, column: Int) {
        replaceCharacters(in: &sequence, column: column, length: 0, with: insertion)
    }

    nonisolated private static func isGap(_ scalar: UnicodeScalar) -> Bool {
        scalar.value == 45 || scalar.value == 46
    }

    nonisolated private static func isGap(_ residue: UInt16) -> Bool {
        residue == 45 || residue == 46
    }
}
