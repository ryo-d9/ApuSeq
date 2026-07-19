import AppKit
import Foundation

struct RenderedAlignment {
    let sequenceAttributedText: NSAttributedString
    let nameAttributedText: NSAttributedString
    let nameColumnWidth: CGFloat
    let identityByColumn: [Double]
    let majorityResidueByColumn: [UInt16]
    let namesChecksum: UInt64
    let sequenceChecksum: UInt64

    static let empty = RenderedAlignment(
        sequenceAttributedText: NSAttributedString(string: ""),
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
    static func render(
        _ alignment: AlignmentData,
        needsIdentityByColumn: Bool,
        needsMajorityResidueByColumn: Bool,
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
        let majorityResidueByColumn = needsMajorityResidueByColumn ? majorityResidues(rows: alignment.rows) : []
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
        }

        let nameColumnWidth = CGFloat(nameWidth + 2) * CGFloat(fontSize * 0.64) + 20
        return RenderedAlignment(
            sequenceAttributedText: sequenceAttributed,
            nameAttributedText: namesAttributed,
            nameColumnWidth: nameColumnWidth,
            identityByColumn: identityByColumn,
            majorityResidueByColumn: majorityResidueByColumn,
            namesChecksum: UInt64(bitPattern: Int64(namesHasher.finalize())),
            sequenceChecksum: UInt64(bitPattern: Int64(sequenceHasher.finalize()))
        )
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

    private static func majorityResidues(rows: [AlignmentRow]) -> [UInt16] {
        guard let length = rows.first?.sequence.count, length > 0 else { return [] }
        let sequences = rows.map { $0.sequence as NSString }
        var majority: [UInt16] = Array(repeating: 0, count: length)
        var counts: [Int] = Array(repeating: 0, count: 128)
        var touched: [Int] = []
        touched.reserveCapacity(16)

        for column in 0..<length {
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

            majority[column] = UInt16(bestBucket)
            for bucket in touched {
                counts[bucket] = 0
            }
            touched.removeAll(keepingCapacity: true)
        }

        return majority
    }
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
    static func backgroundColor(for identity: Double, threshold: Double) -> NSColor? {
        let clamped = min(max(identity, 0), 1)
        let clampedThreshold = min(max(threshold, 0), 1)
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
    static func isDefined(_ residue: UInt16) -> Bool {
        color(for: residue) != nil
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

func normalizedResidueCode(_ residue: UInt16) -> UInt16 {
    if residue == 46 { return 45 }
    if residue >= 97 && residue <= 122 { return residue - 32 }
    return residue
}
