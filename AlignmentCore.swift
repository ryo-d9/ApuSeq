import AppKit
import Foundation

struct RenderedAlignment {
    let sequenceAttributedText: NSAttributedString
    let nameAttributedText: NSAttributedString
    let nameColumnWidth: CGFloat
    let identityByColumn: [Double]
    let namesChecksum: UInt64
    let sequenceChecksum: UInt64

    static let empty = RenderedAlignment(
        sequenceAttributedText: NSAttributedString(string: ""),
        nameAttributedText: NSAttributedString(string: ""),
        nameColumnWidth: 120,
        identityByColumn: [],
        namesChecksum: 0,
        sequenceChecksum: 0
    )
}

struct RenderedFingerprint: Equatable {
    let namesChecksum: UInt64
    let sequenceChecksum: UInt64
    let nameLength: Int
    let sequenceLength: Int

    static let empty = RenderedFingerprint(
        namesChecksum: 0,
        sequenceChecksum: 0,
        nameLength: 0,
        sequenceLength: 0
    )
}

enum AlignmentRenderer {
    static func render(
        _ alignment: AlignmentData,
        showsResidueColors: Bool,
        needsIdentityByColumn: Bool,
        fontSize: Double
    ) -> RenderedAlignment {
        guard !alignment.rows.isEmpty else { return .empty }

        let nameWidth = alignment.rows.map { $0.name.count }.max() ?? 0
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
            .foregroundColor: NSColor.labelColor
        ]
        let nameAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        let namesAttributed = NSMutableAttributedString()
        let sequenceAttributed = NSMutableAttributedString()
        let identityByColumn = needsIdentityByColumn ? columnIdentity(rows: alignment.rows) : []
        var namesHasher = Hasher()
        var sequenceHasher = Hasher()

        for row in alignment.rows {
            let paddedName = row.name.padding(toLength: nameWidth, withPad: " ", startingAt: 0)
            let nameLine = paddedName + "\n"
            let sequenceLine = row.sequence + "\n"
            namesHasher.combine(nameLine)
            sequenceHasher.combine(sequenceLine)

            let sequenceLineStart = sequenceAttributed.length

            namesAttributed.append(NSAttributedString(string: nameLine, attributes: nameAttributes))
            sequenceAttributed.append(NSAttributedString(string: sequenceLine, attributes: baseAttributes))

            sequenceAttributed.addAttribute(
                .residueSymbol,
                value: true,
                range: NSRange(location: sequenceLineStart, length: (row.sequence as NSString).length)
            )

            if showsResidueColors {
                applyResidueColors(
                    sequence: row.sequence,
                    to: sequenceAttributed,
                    lineStart: sequenceLineStart
                )
            }

        }

        let nameColumnWidth = CGFloat(nameWidth + 2) * CGFloat(fontSize * 0.64) + 20
        return RenderedAlignment(
            sequenceAttributedText: sequenceAttributed,
            nameAttributedText: namesAttributed,
            nameColumnWidth: nameColumnWidth,
            identityByColumn: identityByColumn,
            namesChecksum: UInt64(bitPattern: Int64(namesHasher.finalize())),
            sequenceChecksum: UInt64(bitPattern: Int64(sequenceHasher.finalize()))
        )
    }

    private static func applyResidueColors(sequence: String, to attributed: NSMutableAttributedString, lineStart: Int) {
        let residues = sequence as NSString
        guard residues.length > 0 else { return }
        var runStart = 0
        var currentColor = ResiduePalette.color(for: residues.character(at: 0))

        for index in 1...residues.length {
            let nextColor: NSColor?
            if index < residues.length {
                nextColor = ResiduePalette.color(for: residues.character(at: index))
            } else {
                nextColor = nil
            }

            if nextColor == currentColor { continue }

            if let color = currentColor {
                attributed.addAttribute(
                    .foregroundColor,
                    value: color,
                    range: NSRange(location: lineStart + runStart, length: index - runStart)
                )
            }

            runStart = index
            currentColor = nextColor
        }
    }

    private static func columnIdentity(rows: [AlignmentRow]) -> [Double] {
        guard let length = rows.first?.sequence.count, length > 0 else { return [] }
        let sequences = rows.map { $0.sequence as NSString }
        var identity: [Double] = Array(repeating: 0, count: length)
        var counts: [Int] = Array(repeating: 0, count: 128)
        var touched: [Int] = []
        touched.reserveCapacity(16)

        for column in 0..<length {
            var totalCount = 0
            var mostCommonCount = 0

            for sequence in sequences {
                guard column < sequence.length else { continue }
                guard let bucket = residueBucketIndex(sequence.character(at: column)) else { continue }
                if counts[bucket] == 0 {
                    touched.append(bucket)
                }
                counts[bucket] += 1
                if counts[bucket] > mostCommonCount {
                    mostCommonCount = counts[bucket]
                }
                totalCount += 1
            }

            guard totalCount > 0 else {
                identity[column] = 0
                for bucket in touched {
                    counts[bucket] = 0
                }
                touched.removeAll(keepingCapacity: true)
                continue
            }
            identity[column] = Double(mostCommonCount) / Double(totalCount)
            for bucket in touched {
                counts[bucket] = 0
            }
            touched.removeAll(keepingCapacity: true)
        }

        return identity
    }

    private static func residueBucketIndex(_ residue: UInt16) -> Int? {
        let normalized = normalizedResidueCode(residue)
        guard normalized < 128 else { return nil }
        return Int(normalized)
    }
}

private func normalizedResidueCode(_ residue: UInt16) -> UInt16 {
    if residue == 46 { return 45 }
    if residue >= 97 && residue <= 122 { return residue - 32 }
    return residue
}

enum AlignmentStatistics {
    static func consensusSequence(rows: [AlignmentRow], length: Int) -> String {
        guard !rows.isEmpty, length > 0 else { return String(repeating: "-", count: max(length, 0)) }

        let sequences = rows.map { $0.sequence as NSString }
        var result = String()
        result.reserveCapacity(length)

        var counts: [Int] = Array(repeating: 0, count: 128)
        var touched: [Int] = []
        touched.reserveCapacity(24)

        for column in 0..<length {
            var bestBucket = -1
            var bestCount = 0

            for sequence in sequences {
                guard column < sequence.length else { continue }
                let residue = normalizedResidueCode(sequence.character(at: column))
                if residue == 45 { continue }
                guard residue < 128 else { continue }
                let bucket = Int(residue)
                if counts[bucket] == 0 {
                    touched.append(bucket)
                }
                counts[bucket] += 1
                if counts[bucket] > bestCount {
                    bestCount = counts[bucket]
                    bestBucket = bucket
                }
            }

            if bestBucket >= 0, let scalar = UnicodeScalar(bestBucket) {
                result.append(Character(scalar))
            } else {
                result.append("-")
            }

            for bucket in touched {
                counts[bucket] = 0
            }
            touched.removeAll(keepingCapacity: true)
        }

        return result
    }
}

enum IdentityPalette {
    static func backgroundColor(for identity: Double, threshold: Double) -> NSColor {
        let clamped = min(max(identity, 0), 1)
        let clampedThreshold = min(max(threshold, 0), 1)
        if clamped >= 1.0 {
            return NSColor.systemBlue.withAlphaComponent(0.60)
        }
        if clamped >= clampedThreshold {
            return NSColor.systemBlue.withAlphaComponent(0.32)
        }
        return NSColor.systemBlue.withAlphaComponent(0.12)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}

extension NSAttributedString.Key {
    static let residueSymbol = NSAttributedString.Key("ApuSeq.ResidueSymbol")
}

enum ResiduePalette {
    static func color(for residue: UInt16) -> NSColor? {
        if let scalar = UnicodeScalar(residue) {
            return color(for: Character(scalar))
        }
        return nil
    }

    static func color(for residue: Character) -> NSColor? {
        switch residue.uppercased().first {
        case "A":
            return NSColor.systemGreen
        case "C":
            return NSColor.systemBlue
        case "G":
            return NSColor.systemOrange
        case "T", "U":
            return NSColor.systemRed
        case "-", ".":
            return NSColor.tertiaryLabelColor
        case "R", "K", "H":
            return NSColor.systemPurple
        case "D", "E":
            return NSColor.systemPink
        case "S", "N", "Q":
            return NSColor.systemTeal
        case "F", "W", "Y", "L", "I", "V", "M":
            return NSColor.systemBrown
        case "P", "X", "B", "Z", "J", "O":
            return NSColor.secondaryLabelColor
        default:
            return nil
        }
    }
}

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
