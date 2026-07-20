import Foundation

enum AlignmentClusterer {
    nonisolated private static let maximumUPGMARowCount = 400

    nonisolated static func upgmaOrderedRows(_ rows: [AlignmentRow]) -> [AlignmentRow] {
        guard rows.count > 2 else { return rows }
        guard rows.count <= maximumUPGMARowCount else { return rows }

        let count = rows.count
        let sequences = rows.map { $0.sequence as NSString }
        var distances = Array(repeating: 0.0, count: count * count)
        var members = rows.indices.map { [$0] }
        var sizes = Array(repeating: 1, count: count)
        var isActive = Array(repeating: true, count: count)
        var activeCount = count

        for row in 0..<count {
            for column in (row + 1)..<count {
                let distance = sequenceDistance(sequences[row], sequences[column])
                distances[(row * count) + column] = distance
                distances[(column * count) + row] = distance
            }
        }

        while activeCount > 1 {
            var bestLeft = -1
            var bestRight = -1
            var bestDistance = Double.greatestFiniteMagnitude

            for left in 0..<count where isActive[left] {
                for right in (left + 1)..<count where isActive[right] {
                    let distance = distances[(left * count) + right]
                    if distance < bestDistance {
                        bestDistance = distance
                        bestLeft = left
                        bestRight = right
                    }
                }
            }

            guard bestLeft >= 0, bestRight >= 0 else { break }
            let leftSize = sizes[bestLeft]
            let rightSize = sizes[bestRight]
            let mergedSize = leftSize + rightSize

            for index in 0..<count where isActive[index] && index != bestLeft && index != bestRight {
                let leftDistance = distances[(bestLeft * count) + index]
                let rightDistance = distances[(bestRight * count) + index]
                let mergedDistance = ((leftDistance * Double(leftSize)) + (rightDistance * Double(rightSize))) / Double(mergedSize)
                distances[(bestLeft * count) + index] = mergedDistance
                distances[(index * count) + bestLeft] = mergedDistance
            }

            members[bestLeft].append(contentsOf: members[bestRight])
            members[bestRight].removeAll(keepingCapacity: false)
            sizes[bestLeft] = mergedSize
            sizes[bestRight] = 0
            isActive[bestRight] = false
            activeCount -= 1
        }

        guard let root = isActive.firstIndex(of: true) else { return rows }
        return members[root].map { rows[$0] }
    }

    nonisolated private static func sequenceDistance(_ first: NSString, _ second: NSString) -> Double {
        let length = min(first.length, second.length)
        guard length > 0 else { return 1 }

        var comparable = 0
        var mismatches = 0
        for index in 0..<length {
            let left = normalizedResidueCode(first.character(at: index))
            let right = normalizedResidueCode(second.character(at: index))
            guard ResiduePalette.isDefined(left), ResiduePalette.isDefined(right) else { continue }
            comparable += 1
            if left != right {
                mismatches += 1
            }
        }

        guard comparable > 0 else { return 1 }
        return Double(mismatches) / Double(comparable)
    }
}
