import Foundation

nonisolated struct ReadPairAssemblyParameters: Sendable {
    let minimumOverlapLength: Int
    let minimumIdentity: Double

    static let `default` = ReadPairAssemblyParameters(
        minimumOverlapLength: 10,
        minimumIdentity: 0.7
    )
}

nonisolated enum ReadPairAssemblyError: LocalizedError {
    case requiresTwoSequences
    case requiresNucleotideSequences
    case emptySequence
    case noSufficientOverlap

    var errorDescription: String? {
        switch self {
        case .requiresTwoSequences:
            return String(localized: "Exactly two nucleotide sequences are required.")
        case .requiresNucleotideSequences:
            return String(localized: "Read-pair assembly is available only for nucleotide sequences.")
        case .emptySequence:
            return String(localized: "Both reads must contain nucleotide sequence data.")
        case .noSufficientOverlap:
            return String(localized: "No sufficient overlap was found.")
        }
    }
}

nonisolated enum ReadPairAssembler {
    nonisolated private struct Candidate {
        let secondOffset: Int
        let overlapLength: Int
        let matchCount: Int
        let mismatchCount: Int

        var informativeLength: Int { matchCount + mismatchCount }
        var score: Int { matchCount - mismatchCount }
        var identity: Double { Double(matchCount) / Double(informativeLength) }
    }

    nonisolated static func assemble(
        rows: [AlignmentRow],
        parameters: ReadPairAssemblyParameters = .default
    ) throws -> [AlignmentRow] {
        guard rows.count == 2 else {
            throw ReadPairAssemblyError.requiresTwoSequences
        }
        guard AlignmentParser.normalize(rows: rows, format: .fasta).sequenceKind == .nucleotide else {
            throw ReadPairAssemblyError.requiresNucleotideSequences
        }

        let first = normalizedBases(rows[0].sequence)
        let second = normalizedBases(rows[1].sequence)
        guard !first.isEmpty, !second.isEmpty else {
            throw ReadPairAssemblyError.emptySequence
        }

        let shorterLength = min(first.count, second.count)
        let minimumOverlap = min(max(parameters.minimumOverlapLength, 1), shorterLength)
        var bestCandidate: Candidate?

        let firstOffset = -(second.count - minimumOverlap)
        let lastOffset = first.count - minimumOverlap
        for secondOffset in firstOffset...lastOffset {
            try Task.checkCancellation()
            let overlapStart = max(0, secondOffset)
            let overlapEnd = min(first.count, secondOffset + second.count)
            let overlapLength = overlapEnd - overlapStart
            guard overlapLength >= minimumOverlap else { continue }

            var matches = 0
            var mismatches = 0
            for firstIndex in overlapStart..<overlapEnd {
                let firstBase = first[firstIndex]
                let secondBase = second[firstIndex - secondOffset]
                guard isUnambiguousBase(firstBase), isUnambiguousBase(secondBase) else {
                    continue
                }
                if firstBase == secondBase {
                    matches += 1
                } else {
                    mismatches += 1
                }
            }
            let candidate = Candidate(
                secondOffset: secondOffset,
                overlapLength: overlapLength,
                matchCount: matches,
                mismatchCount: mismatches
            )
            guard candidate.informativeLength >= minimumOverlap else { continue }
            guard candidate.identity >= parameters.minimumIdentity else { continue }
            if isBetter(candidate, than: bestCandidate) {
                bestCandidate = candidate
            }
        }

        guard let bestCandidate else {
            throw ReadPairAssemblyError.noSufficientOverlap
        }
        return positionedRows(
            rows,
            first: first,
            second: second,
            secondOffset: bestCandidate.secondOffset
        )
    }

    nonisolated private static func isUnambiguousBase(_ base: UInt8) -> Bool {
        base == 65 || base == 67 || base == 71 || base == 84
    }

    nonisolated private static func normalizedBases(_ sequence: String) -> [UInt8] {
        sequence.utf8.compactMap { byte in
            switch byte {
            case 45, 46, 9, 10, 13, 32:
                return nil
            case 97...122:
                let uppercase = byte - 32
                return uppercase == 85 ? 84 : uppercase
            case 85:
                return 84
            default:
                return byte
            }
        }
    }

    nonisolated private static func isBetter(_ candidate: Candidate, than current: Candidate?) -> Bool {
        guard let current else { return true }
        if candidate.score != current.score { return candidate.score > current.score }
        if candidate.identity != current.identity { return candidate.identity > current.identity }
        if candidate.overlapLength != current.overlapLength { return candidate.overlapLength > current.overlapLength }
        if candidate.mismatchCount != current.mismatchCount { return candidate.mismatchCount < current.mismatchCount }
        if abs(candidate.secondOffset) != abs(current.secondOffset) {
            return abs(candidate.secondOffset) < abs(current.secondOffset)
        }
        return candidate.secondOffset < current.secondOffset
    }

    nonisolated private static func positionedRows(
        _ rows: [AlignmentRow],
        first: [UInt8],
        second: [UInt8],
        secondOffset: Int
    ) -> [AlignmentRow] {
        let start = min(0, secondOffset)
        let end = max(first.count, secondOffset + second.count)
        let firstSequence = String(repeating: "-", count: -start)
            + String(decoding: first, as: UTF8.self)
            + String(repeating: "-", count: end - first.count)
        let secondSequence = String(repeating: "-", count: secondOffset - start)
            + String(decoding: second, as: UTF8.self)
            + String(repeating: "-", count: end - secondOffset - second.count)

        return [
            AlignmentRow(name: rows[0].name, sequence: firstSequence),
            AlignmentRow(name: rows[1].name, sequence: secondSequence)
        ]
    }
}
