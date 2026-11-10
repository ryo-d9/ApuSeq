import AppKit
import Foundation

struct RenderedAlignment: @unchecked Sendable {
    let sequenceText: String?
    let nameAttributedText: NSAttributedString
    let nameColumnWidth: CGFloat
    let identityByColumn: [Float]
    let majorityResidueByColumn: [UInt8]
    let namesChecksum: UInt64
    let sequenceChecksum: UInt64

    nonisolated static let empty = RenderedAlignment(
        sequenceText: "",
        nameAttributedText: NSAttributedString(string: ""),
        nameColumnWidth: 120,
        identityByColumn: [],
        majorityResidueByColumn: [],
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
    nonisolated static func render(
        _ alignment: AlignmentData,
        rowIndices: [Int]? = nil,
        needsIdentityByColumn: Bool,
        needsMajorityResidueByColumn: Bool,
        includesSequenceText: Bool = true,
        previousIdentityByColumn: [Float] = [],
        previousMajorityResidueByColumn: [UInt8] = [],
        changedColumns: Range<Int>? = nil,
        fontSize: Double
    ) -> RenderedAlignment {
        guard !alignment.rows.isEmpty, !Task.isCancelled else { return .empty }

        let resolvedRowIndices = rowIndices ?? Array(alignment.rows.indices)
        let rows = resolvedRowIndices.map { alignment.rows[$0] }
        let nameWidth = rows.map { $0.name.count }.max() ?? 0
        let baseFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let nameAttributes: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        let namesAttributed = NSMutableAttributedString()
        var sequenceText: String? = includesSequenceText ? String() : nil
        if includesSequenceText {
            sequenceText?.reserveCapacity(rows.reduce(0) { $0 + ($1.sequence as NSString).length + 1 })
        }
        let identityByColumn = needsIdentityByColumn
            ? AlignmentStatistics.columnIdentity(
                rows: rows,
                previous: previousIdentityByColumn,
                changedColumns: changedColumns
            )
            : []
        let majorityResidueByColumn = needsMajorityResidueByColumn
            ? AlignmentStatistics.majorityResidues(
                rows: rows,
                previous: previousMajorityResidueByColumn,
                changedColumns: changedColumns
            )
            : []
        var namesHasher = Hasher()
        var sequenceHasher = Hasher()

        for row in rows {
            guard !Task.isCancelled else { return .empty }
            let paddedName = row.name.padding(toLength: nameWidth, withPad: " ", startingAt: 0)
            let nameLine = paddedName + "\n"
            let sequenceLine = row.sequence + "\n"
            namesHasher.combine(nameLine)
            sequenceHasher.combine(sequenceLine)

            namesAttributed.append(NSAttributedString(string: nameLine, attributes: nameAttributes))
            sequenceText?.append(sequenceLine)
        }

        let nameColumnWidth = AlignmentStatistics.nameColumnWidth(rows: rows, font: baseFont)
        return RenderedAlignment(
            sequenceText: sequenceText,
            nameAttributedText: namesAttributed,
            nameColumnWidth: nameColumnWidth,
            identityByColumn: identityByColumn,
            majorityResidueByColumn: majorityResidueByColumn,
            namesChecksum: UInt64(bitPattern: Int64(namesHasher.finalize())),
            sequenceChecksum: UInt64(bitPattern: Int64(sequenceHasher.finalize()))
        )
    }
}

enum AlignmentStatistics {
    nonisolated static func nameColumnWidth(rows: [AlignmentRow], font: NSFont) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let nameTextWidth = rows
            .map { ($0.name as NSString).size(withAttributes: attributes).width }
            .max() ?? 0
        let horizontalPadding = (("M" as NSString).size(withAttributes: attributes).width * 2) + 20
        return ceil(nameTextWidth + horizontalPadding)
    }

    nonisolated static func columnIdentity(rows: [AlignmentRow]) -> [Float] {
        columnIdentity(rows: rows, previous: [], changedColumns: nil)
    }

    nonisolated static func columnIdentity(
        rows: [AlignmentRow],
        previous: [Float],
        changedColumns: Range<Int>?
    ) -> [Float] {
        guard let length = rows.first?.sequence.count, length > 0 else { return [] }
        let sequences = rows.map { $0.sequence as NSString }
        var identity = resized(previous, to: length, defaultValue: 0)
        let columns = resolvedColumns(changedColumns, existingCount: previous.count, length: length)
        var counts: [Int] = Array(repeating: 0, count: 128)
        var touched: [Int] = []
        touched.reserveCapacity(16)

        for column in columns {
            if Task.isCancelled { return identity }
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
            identity[column] = Float(mostCommonCount) / Float(totalCount)
            for bucket in touched {
                counts[bucket] = 0
            }
            touched.removeAll(keepingCapacity: true)
        }

        return identity
    }

    static func consensusSequence(rows: [AlignmentRow], length: Int) -> String {
        guard !rows.isEmpty, length > 0 else { return String(repeating: "-", count: max(length, 0)) }

        let sequences = rows.map { $0.sequence as NSString }
        var result = String()
        result.reserveCapacity(length)

        var counts: [Int] = Array(repeating: 0, count: 128)
        var touched: [Int] = []
        touched.reserveCapacity(24)

        for column in 0..<length {
            if Task.isCancelled { return result }
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

    nonisolated static func majorityResidues(rows: [AlignmentRow]) -> [UInt8] {
        majorityResidues(rows: rows, previous: [], changedColumns: nil)
    }

    nonisolated static func majorityResidues(
        rows: [AlignmentRow],
        previous: [UInt8],
        changedColumns: Range<Int>?
    ) -> [UInt8] {
        guard let length = rows.first?.sequence.count, length > 0 else { return [] }
        let sequences = rows.map { $0.sequence as NSString }
        var majority = resized(previous, to: length, defaultValue: 0)
        let columns = resolvedColumns(changedColumns, existingCount: previous.count, length: length)
        var counts: [Int] = Array(repeating: 0, count: 128)
        var touched: [Int] = []
        touched.reserveCapacity(16)

        for column in columns {
            if Task.isCancelled { return majority }
            var bestBucket = 0
            var bestCount = 0

            for sequence in sequences {
                guard column < sequence.length else { continue }
                let residue = normalizedResidueCode(sequence.character(at: column))
                guard residue < 128, ResiduePalette.isDefined(residue) else { continue }
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

            majority[column] = UInt8(bestBucket)
            for bucket in touched {
                counts[bucket] = 0
            }
            touched.removeAll(keepingCapacity: true)
        }

        return majority
    }

    nonisolated private static func resolvedColumns(
        _ requested: Range<Int>?,
        existingCount: Int,
        length: Int
    ) -> Range<Int> {
        guard existingCount > 0, let requested else { return 0..<length }
        let lowerBound = min(max(requested.lowerBound, 0), length)
        let upperBound = min(max(requested.upperBound, lowerBound), length)
        return lowerBound..<upperBound
    }

    nonisolated private static func resized<Element>(
        _ values: [Element],
        to count: Int,
        defaultValue: Element
    ) -> [Element] {
        if values.count == count { return values }
        if values.count > count { return Array(values.prefix(count)) }
        return values + Array(repeating: defaultValue, count: count - values.count)
    }

    nonisolated private static func residueBucketIndex(_ residue: UInt16) -> Int? {
        let normalized = normalizedResidueCode(residue)
        guard normalized < 128 else { return nil }
        return Int(normalized)
    }
}

enum IdentityPalette {
    static func backgroundColor(for identity: Float, threshold: Double) -> NSColor? {
        let clamped = min(max(identity, 0), 1)
        let clampedThreshold = Float(min(max(threshold, 0), 1))
        if clamped >= 1.0 {
            return NSColor.systemBlue.withAlphaComponent(0.56)
        }
        let highBand = clampedThreshold + ((1.0 - clampedThreshold) * 0.5)
        if clamped >= highBand {
            return NSColor.systemBlue.withAlphaComponent(0.40)
        }
        if clamped >= clampedThreshold {
            return NSColor.systemBlue.withAlphaComponent(0.26)
        }
        if clamped >= clampedThreshold * 0.5 {
            return NSColor.systemBlue.withAlphaComponent(0.14)
        }
        return nil
    }
}

enum IdentityBars {
    nonisolated private static let glyphs: [Character] = [" ", "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]

    nonisolated static func barIndex(for value: Float) -> Int {
        let clamped = min(max(value, 0), 1)
        return min(Int((clamped * 8.0).rounded()), 8)
    }

    nonisolated static func barString<C: Collection>(from values: C) -> String where C.Element == Float {
        var output = String()
        output.reserveCapacity(values.count)
        for value in values {
            output.append(glyphs[barIndex(for: value)])
        }
        return output
    }
}

enum ReferenceDifferencePalette {
    static func backgroundColor(for residue: UInt16, referenceResidue: UInt16?) -> NSColor? {
        let normalizedResidue = normalizedResidueCode(residue)
        guard let referenceResidue else { return nil }
        guard normalizedResidue != normalizedResidueCode(referenceResidue) else { return nil }
        return ResiduePalette.backgroundColor(for: normalizedResidue)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}

enum ResiduePalette {
    nonisolated static func isDefined(_ residue: UInt16) -> Bool {
        switch normalizedResidueCode(residue) {
        case 65, 67, 71, 84, 85, 82, 75, 72, 68, 69, 83, 78, 81, 70, 87, 89, 76, 73, 86, 77, 80, 88, 66, 90, 74, 79:
            return true
        default:
            return false
        }
    }

    static func backgroundColor(for residue: UInt16) -> NSColor? {
        color(for: residue)?.withAlphaComponent(0.22)
    }

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

nonisolated func normalizedResidueCode(_ residue: UInt16) -> UInt16 {
    if residue == 46 { return 45 }
    if residue >= 97 && residue <= 122 { return residue - 32 }
    return residue
}
