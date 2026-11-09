import Foundation
import Observation

@Observable
@MainActor
final class AlignmentViewModel {
    var alignment: AlignmentData = .empty
    var renderedAlignment: RenderedAlignment = .empty
    var displayedRowIndices: [Int] = []
    var renderedDisplayOrderMode: AlignmentDisplayOrderMode = .original
    var parseErrorMessage: String?
    var contentVersion = 0

    private(set) var alignmentVersion = 0
    private var parseTask: Task<Void, Never>?
    private var renderTask: Task<Void, Never>?
    private var cachedRenderVersion = -1
    private var cachedRenderFontSize = -1.0
    private var cachedRenderIdentityMode = false
    private var cachedRenderMajorityMode = false
    private var cachedRenderOrderMode: AlignmentDisplayOrderMode = .original
    private var cachedRenderIncludesSequenceText = false
    private var cachedAlignment: RenderedAlignment?
    private var cachedDisplayedRowIndices: [Int] = []
    private var cachedConsensusKey: ConsensusKey?
    private var cachedConsensus: String = ""
    private var cachedAuxiliaryKey: AuxiliaryKey?
    private var cachedAuxiliaryContent: AuxiliaryPanelContent = .empty
    private var pendingEditorChangedColumns: Range<Int>?

    func parseAndRender(
        rawText: String,
        fontSize: Double,
        needsIdentityByColumn: Bool,
        needsMajorityResidueByColumn: Bool,
        displayOrderMode: AlignmentDisplayOrderMode,
        referenceName: String?
    ) {
        parseTask?.cancel()
        renderTask?.cancel()

        guard !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            alignment = .empty
            alignmentVersion += 1
            renderedAlignment = .empty
            displayedRowIndices = []
            renderedDisplayOrderMode = .original
            parseErrorMessage = nil
            contentVersion += 1
            clearCache()
            return
        }

        parseTask = Task(priority: .userInitiated) {
            do {
                let parsed = try await runOnBackgroundThrowing {
                    try AlignmentParser.parse(rawText)
                }
                try Task.checkCancellation()
                await MainActor.run {
                    alignment = parsed
                    alignmentVersion += 1
                    parseErrorMessage = nil
                    clearCache()
                    rerender(
                        fontSize: fontSize,
                        needsIdentityByColumn: needsIdentityByColumn,
                        needsMajorityResidueByColumn: needsMajorityResidueByColumn,
                        displayOrderMode: displayOrderMode,
                        referenceName: referenceName
                    )
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    alignment = .empty
                    alignmentVersion += 1
                    renderedAlignment = .empty
                    displayedRowIndices = []
                    renderedDisplayOrderMode = .original
                    parseErrorMessage = error.localizedDescription
                    clearCache()
                    contentVersion += 1
                }
            }
        }
    }

    func rerender(
        fontSize: Double,
        needsIdentityByColumn: Bool,
        needsMajorityResidueByColumn: Bool,
        displayOrderMode: AlignmentDisplayOrderMode,
        referenceName: String?,
        preservesTextStorage: Bool = false
    ) {
        renderTask?.cancel()
        let includesSequenceText = !preservesTextStorage

        let cacheKeyMatches =
            cachedRenderVersion == alignmentVersion &&
            abs(cachedRenderFontSize - fontSize) < 0.001 &&
            cachedRenderIdentityMode == needsIdentityByColumn &&
            cachedRenderMajorityMode == needsMajorityResidueByColumn &&
            cachedRenderOrderMode == displayOrderMode &&
            cachedRenderIncludesSequenceText == includesSequenceText

        if !cacheKeyMatches {
            cachedRenderVersion = alignmentVersion
            cachedRenderFontSize = fontSize
            cachedRenderIdentityMode = needsIdentityByColumn
            cachedRenderMajorityMode = needsMajorityResidueByColumn
            cachedRenderOrderMode = displayOrderMode
            cachedRenderIncludesSequenceText = includesSequenceText
            cachedAlignment = nil
            cachedDisplayedRowIndices = []
        }

        if let cachedAlignment {
            apply(
                cachedAlignment,
                displayedRowIndices: cachedDisplayedRowIndices,
                displayOrderMode: displayOrderMode,
                preservesTextStorage: preservesTextStorage
            )
            return
        }

        let baseRows = alignment.rows
        let format = alignment.format
        let length = alignment.length
        let sequenceKind = alignment.sequenceKind
        let currentVersion = alignmentVersion

        renderTask = Task(priority: .userInitiated) {
            let renderResult: (RenderedAlignment, [Int]) = await runOnBackground {
                let orderedIndices: [Int]
                switch displayOrderMode {
                case .original:
                    orderedIndices = Array(baseRows.indices)
                case .name:
                    orderedIndices = AlignmentRowOrdering.orderedIndicesByName(baseRows)
                case .upgma:
                    orderedIndices = AlignmentRowOrdering.upgmaOrderedIndices(baseRows)
                }
                let sourceAlignment = AlignmentData(
                    format: format,
                    rows: baseRows,
                    length: length,
                    sequenceKind: sequenceKind
                )
                let rendered = AlignmentRenderer.render(
                    sourceAlignment,
                    rowIndices: orderedIndices,
                    needsIdentityByColumn: needsIdentityByColumn,
                    needsMajorityResidueByColumn: needsMajorityResidueByColumn,
                    includesSequenceText: includesSequenceText,
                    fontSize: fontSize
                )
                return (rendered, orderedIndices)
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard currentVersion == alignmentVersion else { return }
                cachedAlignment = renderResult.0
                cachedDisplayedRowIndices = renderResult.1
                apply(
                    renderResult.0,
                    displayedRowIndices: renderResult.1,
                    displayOrderMode: displayOrderMode,
                    preservesTextStorage: preservesTextStorage
                )
            }
        }
    }

    func applyEditorAlignment(
        _ editedAlignment: AlignmentData,
        changedColumns: Range<Int>,
        fontSize: Double,
        needsIdentityByColumn: Bool,
        needsMajorityResidueByColumn: Bool,
        referenceName: String?
    ) {
        parseTask?.cancel()
        renderTask?.cancel()
        let accumulatedChangedColumns: Range<Int>
        if let pendingEditorChangedColumns {
            if alignment.length == editedAlignment.length {
                accumulatedChangedColumns = min(pendingEditorChangedColumns.lowerBound, changedColumns.lowerBound)..<max(
                    pendingEditorChangedColumns.upperBound,
                    changedColumns.upperBound
                )
            } else {
                accumulatedChangedColumns = 0..<editedAlignment.length
            }
        } else {
            accumulatedChangedColumns = changedColumns
        }
        let previousIdentityByColumn = renderedAlignment.identityByColumn
        let previousMajorityResidueByColumn = renderedAlignment.majorityResidueByColumn
        alignment = editedAlignment
        alignmentVersion += 1
        parseErrorMessage = nil
        clearCache()
        pendingEditorChangedColumns = accumulatedChangedColumns
        renderEditorAlignment(
            fontSize: fontSize,
            needsIdentityByColumn: needsIdentityByColumn,
            needsMajorityResidueByColumn: needsMajorityResidueByColumn,
            previousIdentityByColumn: previousIdentityByColumn,
            previousMajorityResidueByColumn: previousMajorityResidueByColumn,
            changedColumns: accumulatedChangedColumns
        )
    }

    func applyAlignment(
        _ newAlignment: AlignmentData,
        fontSize: Double,
        needsIdentityByColumn: Bool,
        needsMajorityResidueByColumn: Bool,
        displayOrderMode: AlignmentDisplayOrderMode,
        referenceName: String?
    ) {
        parseTask?.cancel()
        renderTask?.cancel()
        alignment = newAlignment
        alignmentVersion += 1
        parseErrorMessage = nil
        clearCache()
        rerender(
            fontSize: fontSize,
            needsIdentityByColumn: needsIdentityByColumn,
            needsMajorityResidueByColumn: needsMajorityResidueByColumn,
            displayOrderMode: displayOrderMode,
            referenceName: referenceName
        )
    }

    private func renderEditorAlignment(
        fontSize: Double,
        needsIdentityByColumn: Bool,
        needsMajorityResidueByColumn: Bool,
        previousIdentityByColumn: [Float],
        previousMajorityResidueByColumn: [UInt8],
        changedColumns: Range<Int>
    ) {
        let sourceAlignment = alignment
        let currentVersion = alignmentVersion
        renderTask = Task(priority: .userInitiated) {
            let rendered = await runOnBackground {
                AlignmentRenderer.render(
                    sourceAlignment,
                    needsIdentityByColumn: needsIdentityByColumn,
                    needsMajorityResidueByColumn: needsMajorityResidueByColumn,
                    includesSequenceText: false,
                    previousIdentityByColumn: previousIdentityByColumn,
                    previousMajorityResidueByColumn: previousMajorityResidueByColumn,
                    changedColumns: changedColumns,
                    fontSize: fontSize
                )
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard currentVersion == alignmentVersion else { return }
                cachedAlignment = rendered
                cachedDisplayedRowIndices = Array(sourceAlignment.rows.indices)
                apply(
                    rendered,
                    displayedRowIndices: cachedDisplayedRowIndices,
                    displayOrderMode: .original,
                    preservesTextStorage: true
                )
                pendingEditorChangedColumns = nil
            }
        }
    }

    func row(id: AlignmentRowID?) -> AlignmentRow? {
        guard let id else { return nil }
        return alignment.rows.first(where: { $0.id == id })
    }

    func auxiliaryPanelContent(
        referenceID: AlignmentRowID?,
        showsReferencePanel: Bool,
        showsConsensusPanel: Bool,
        showsConservationPanel: Bool
    ) -> AuxiliaryPanelContent {
        let key = AuxiliaryKey(
            alignmentVersion: alignmentVersion,
            referenceID: referenceID,
            showsReferencePanel: showsReferencePanel,
            showsConsensusPanel: showsConsensusPanel,
            showsConservationPanel: showsConservationPanel,
            identityCount: renderedAlignment.identityByColumn.count,
            identityChecksum: renderedAlignment.identityByColumn.reduce(into: 1469598103934665603) { partialResult, value in
                partialResult = (partialResult ^ UInt64(value.bitPattern)) &* 1099511628211
            }
        )
        if key == cachedAuxiliaryKey {
            return cachedAuxiliaryContent
        }

        let rows = alignment.rows
        let referenceRow = row(id: referenceID)
        let referenceText = showsReferencePanel ? (referenceRow?.sequence ?? "") : nil
        let consensus = showsConsensusPanel ? cachedConsensusSequence(rows: rows) : nil
        let conservation = showsConservationPanel ? renderedAlignment.identityByColumn : nil
        let referenceLabel = showsReferencePanel
            ? String(format: String(localized: "Ref: %@"), referenceRow?.name ?? "")
            : nil
        let built = AuxiliaryPanelBuilder.build(
            referenceLabel: referenceLabel,
            referenceSequence: referenceText,
            consensusSequence: consensus,
            conservation: conservation
        )
        cachedAuxiliaryKey = key
        cachedAuxiliaryContent = built
        return built
    }

    func containsRow(id: AlignmentRowID?) -> Bool {
        guard let id else { return false }
        return alignment.rows.contains(where: { $0.id == id })
    }

    func consensusSequence() -> String {
        cachedConsensusSequence(rows: alignment.rows)
    }

    private func apply(
        _ rendered: RenderedAlignment,
        displayedRowIndices: [Int],
        displayOrderMode: AlignmentDisplayOrderMode,
        preservesTextStorage: Bool = false
    ) {
        let textChanged = renderedAlignment.namesChecksum != rendered.namesChecksum ||
            renderedAlignment.sequenceChecksum != rendered.sequenceChecksum ||
            renderedAlignment.nameAttributedText.length != rendered.nameAttributedText.length ||
            renderedAlignment.sequenceText.map { ($0 as NSString).length } != rendered.sequenceText.map { ($0 as NSString).length }
        renderedAlignment = rendered
        self.displayedRowIndices = displayedRowIndices
        renderedDisplayOrderMode = displayOrderMode
        if textChanged && !preservesTextStorage {
            contentVersion += 1
        }
    }

    private func clearCache() {
        cachedAlignment = nil
        cachedDisplayedRowIndices = []
        cachedRenderVersion = -1
        cachedRenderFontSize = -1.0
        cachedRenderIdentityMode = false
        cachedRenderMajorityMode = false
        cachedRenderOrderMode = .original
        cachedRenderIncludesSequenceText = false
        cachedConsensusKey = nil
        cachedConsensus = ""
        cachedAuxiliaryKey = nil
        cachedAuxiliaryContent = .empty
        pendingEditorChangedColumns = nil
    }

    private func cachedConsensusSequence(rows: [AlignmentRow]) -> String {
        let key = ConsensusKey(alignmentVersion: alignmentVersion)
        if key == cachedConsensusKey {
            return cachedConsensus
        }
        let sequence = AlignmentStatistics.consensusSequence(rows: rows, length: alignment.length)
        cachedConsensusKey = key
        cachedConsensus = sequence
        return sequence
    }

    private func runOnBackground<T: Sendable>(_ work: @Sendable @escaping () -> T) async -> T {
        await Task.detached(priority: .userInitiated) {
            work()
        }.value
    }

    private func runOnBackgroundThrowing<T: Sendable>(_ work: @Sendable @escaping () throws -> T) async throws -> T {
        try await Task.detached(priority: .userInitiated) {
            try work()
        }.value
    }

    private struct ConsensusKey: Equatable {
        let alignmentVersion: Int
    }

    private struct AuxiliaryKey: Equatable {
        let alignmentVersion: Int
        let referenceID: AlignmentRowID?
        let showsReferencePanel: Bool
        let showsConsensusPanel: Bool
        let showsConservationPanel: Bool
        let identityCount: Int
        let identityChecksum: UInt64
    }
}

enum AlignmentBackgroundMode: String, CaseIterable, Identifiable {
    case none = "None"
    case residue = "Residue"
    case minority = "Minority"
    case reference = "Reference"
    case identity = "Identity"

    var id: String { rawValue }

    var localizedName: String {
        AppStrings.backgroundName(self)
    }
}

enum AlignmentDisplayOrderMode: String, CaseIterable, Identifiable {
    case original = "Original"
    case name = "Name"
    case upgma = "UPGMA"

    var id: String { rawValue }

    var localizedName: String {
        AppStrings.displayOrderName(self)
    }
}

struct AuxiliaryPanelContent {
    let leftText: String
    let rightText: String
    let lineCount: Int
    let coloredRanges: [NSRange]

    static let empty = AuxiliaryPanelContent(leftText: "", rightText: "", lineCount: 0, coloredRanges: [])
}

private enum AuxiliaryPanelBuilder {
    static func build(
        referenceLabel: String?,
        referenceSequence: String?,
        consensusSequence: String?,
        conservation: [Float]?
    ) -> AuxiliaryPanelContent {
        var left: [String] = []
        var right: [String] = []
        var rightUTF16Length = 0
        var coloredRanges: [NSRange] = []

        func appendLine(label: String, sequence: String, appliesColor: Bool = false) {
            if !right.isEmpty {
                rightUTF16Length += 1
            }
            if appliesColor {
                coloredRanges.append(NSRange(location: rightUTF16Length, length: (sequence as NSString).length))
            }
            left.append(label)
            right.append(sequence)
            rightUTF16Length += (sequence as NSString).length
        }

        if referenceSequence != nil {
            appendLine(label: referenceLabel ?? String(localized: "Ref:"), sequence: referenceSequence ?? "", appliesColor: true)
        }
        if let consensusSequence {
            appendLine(label: String(localized: "Consensus"), sequence: consensusSequence, appliesColor: true)
        }
        if let conservation {
            appendLine(label: String(localized: "Identity"), sequence: IdentityBars.barString(from: conservation))
        }

        return AuxiliaryPanelContent(
            leftText: left.joined(separator: "\n"),
            rightText: right.joined(separator: "\n"),
            lineCount: max(left.count, right.count),
            coloredRanges: coloredRanges
        )
    }

}
