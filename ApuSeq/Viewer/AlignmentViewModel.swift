import Foundation
import Observation

@Observable
@MainActor
final class AlignmentViewModel {
    var alignment: AlignmentData = .empty
    var renderedAlignment: RenderedAlignment = .empty
    var displayedRows: [AlignmentRow] = []
    var renderedDisplayOrderMode: AlignmentDisplayOrderMode = .original
    var parseErrorMessage: String?
    var contentVersion = 0

    private var alignmentVersion = 0
    private var parseTask: Task<Void, Never>?
    private var renderTask: Task<Void, Never>?
    private var cachedRenderVersion = -1
    private var cachedRenderFontSize = -1.0
    private var cachedRenderIdentityMode = false
    private var cachedRenderMajorityMode = false
    private var cachedRenderOrderMode: AlignmentDisplayOrderMode = .original
    private var cachedAlignment: RenderedAlignment?
    private var cachedDisplayedRows: [AlignmentRow] = []
    private var cachedConsensusKey: ConsensusKey?
    private var cachedConsensus: String = ""
    private var cachedAuxiliaryKey: AuxiliaryKey?
    private var cachedAuxiliaryContent: AuxiliaryPanelContent = .empty

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
            renderedAlignment = .empty
            displayedRows = []
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
                    renderedAlignment = .empty
                    displayedRows = []
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
        referenceName: String?
    ) {
        renderTask?.cancel()

        let cacheKeyMatches =
            cachedRenderVersion == alignmentVersion &&
            abs(cachedRenderFontSize - fontSize) < 0.001 &&
            cachedRenderIdentityMode == needsIdentityByColumn &&
            cachedRenderMajorityMode == needsMajorityResidueByColumn &&
            cachedRenderOrderMode == displayOrderMode

        if !cacheKeyMatches {
            cachedRenderVersion = alignmentVersion
            cachedRenderFontSize = fontSize
            cachedRenderIdentityMode = needsIdentityByColumn
            cachedRenderMajorityMode = needsMajorityResidueByColumn
            cachedRenderOrderMode = displayOrderMode
            cachedAlignment = nil
            cachedDisplayedRows = []
        }

        if let cachedAlignment {
            apply(cachedAlignment, displayedRows: cachedDisplayedRows, displayOrderMode: displayOrderMode)
            return
        }

        let baseRows = alignment.rows
        let format = alignment.format
        let length = alignment.length
        let sequenceKind = alignment.sequenceKind
        let currentVersion = alignmentVersion

        renderTask = Task(priority: .userInitiated) {
            let renderResult: (RenderedAlignment, [AlignmentRow]) = await runOnBackground {
                let orderedRows = displayOrderMode == .upgma
                    ? AlignmentClusterer.upgmaOrderedRows(baseRows)
                    : baseRows
                let displayAlignment = AlignmentData(
                    format: format,
                    rows: orderedRows,
                    length: length,
                    sequenceKind: sequenceKind
                )
                let rendered = AlignmentRenderer.render(
                    displayAlignment,
                    needsIdentityByColumn: needsIdentityByColumn,
                    needsMajorityResidueByColumn: needsMajorityResidueByColumn,
                    fontSize: fontSize
                )
                return (rendered, orderedRows)
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard currentVersion == alignmentVersion else { return }
                cachedAlignment = renderResult.0
                cachedDisplayedRows = renderResult.1
                apply(renderResult.0, displayedRows: renderResult.1, displayOrderMode: displayOrderMode)
            }
        }
    }

    func row(named name: String?) -> AlignmentRow? {
        guard let name else { return nil }
        return alignment.rows.first(where: { $0.name == name })
    }

    func auxiliaryPanelContent(
        referenceName: String?,
        showsReferencePanel: Bool,
        showsConsensusPanel: Bool,
        showsConservationPanel: Bool
    ) -> AuxiliaryPanelContent {
        let key = AuxiliaryKey(
            alignmentVersion: alignmentVersion,
            referenceName: referenceName ?? "",
            showsReferencePanel: showsReferencePanel,
            showsConsensusPanel: showsConsensusPanel,
            showsConservationPanel: showsConservationPanel,
            identityCount: renderedAlignment.identityByColumn.count,
            identityChecksum: renderedAlignment.identityByColumn.reduce(into: 1469598103934665603) { partialResult, value in
                partialResult = (partialResult ^ UInt64(bitPattern: Int64(value.bitPattern))) &* 1099511628211
            }
        )
        if key == cachedAuxiliaryKey {
            return cachedAuxiliaryContent
        }

        let rows = alignment.rows
        let referenceText = showsReferencePanel ? (row(named: referenceName)?.sequence ?? "") : nil
        let consensus = showsConsensusPanel ? cachedConsensusSequence(rows: rows) : nil
        let conservation = showsConservationPanel ? renderedAlignment.identityByColumn : nil
        let built = AuxiliaryPanelBuilder.build(
            referenceLabel: showsReferencePanel ? "Ref: \(referenceName ?? "")" : nil,
            referenceSequence: referenceText,
            consensusSequence: consensus,
            conservation: conservation
        )
        cachedAuxiliaryKey = key
        cachedAuxiliaryContent = built
        return built
    }

    func containsRow(named name: String?) -> Bool {
        guard let name else { return false }
        return alignment.rows.contains(where: { $0.name == name })
    }

    func consensusSequence() -> String {
        cachedConsensusSequence(rows: alignment.rows)
    }

    private func apply(
        _ rendered: RenderedAlignment,
        displayedRows: [AlignmentRow],
        displayOrderMode: AlignmentDisplayOrderMode
    ) {
        renderedAlignment = rendered
        self.displayedRows = displayedRows
        renderedDisplayOrderMode = displayOrderMode
        contentVersion += 1
    }

    private func clearCache() {
        cachedAlignment = nil
        cachedDisplayedRows = []
        cachedRenderVersion = -1
        cachedRenderFontSize = -1.0
        cachedRenderIdentityMode = false
        cachedRenderMajorityMode = false
        cachedRenderOrderMode = .original
        cachedConsensusKey = nil
        cachedConsensus = ""
        cachedAuxiliaryKey = nil
        cachedAuxiliaryContent = .empty
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
        let referenceName: String
        let showsReferencePanel: Bool
        let showsConsensusPanel: Bool
        let showsConservationPanel: Bool
        let identityCount: Int
        let identityChecksum: UInt64
    }
}

enum AlignmentBackgroundMode: String, CaseIterable, Identifiable {
    case residue = "Residue"
    case different = "Different"
    case identity = "Identity"

    var id: String { rawValue }

    var localizedName: String {
        AppStrings.backgroundName(self)
    }
}

enum AlignmentDisplayOrderMode: String, CaseIterable, Identifiable {
    case original = "Original"
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
        conservation: [Double]?
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
            appendLine(label: referenceLabel ?? "Ref:", sequence: referenceSequence ?? "", appliesColor: true)
        }
        if let consensusSequence {
            appendLine(label: "Consensus", sequence: consensusSequence, appliesColor: true)
        }
        if let conservation {
            appendLine(label: "Identity", sequence: conservationBars(from: conservation))
        }

        return AuxiliaryPanelContent(
            leftText: left.joined(separator: "\n"),
            rightText: right.joined(separator: "\n"),
            lineCount: max(left.count, right.count),
            coloredRanges: coloredRanges
        )
    }

    private static func conservationBars(from values: [Double]) -> String {
        let glyphs: [Character] = [" ", "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]
        var output = String()
        output.reserveCapacity(values.count)
        for value in values {
            let clamped = min(max(value, 0), 1)
            let index = min(Int((clamped * 8.0).rounded()), 8)
            output.append(glyphs[index])
        }
        return output
    }
}
