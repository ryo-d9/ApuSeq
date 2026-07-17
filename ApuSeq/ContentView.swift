//
//  ContentView.swift
//  ApuSeq
//
//  Created by 須田崚 on 2026/04/27.
//

import Observation
import SwiftUI

struct ContentView: View {
    @ObservedObject var document: ApuSeqDocument

    var body: some View {
        RootView(document: document)
    }
}

@Observable
@MainActor
private final class AlignmentViewModel {
    var alignment: AlignmentData = .empty
    var renderedAlignment: RenderedAlignment = .empty
    var parseErrorMessage: String?
    var contentVersion = 0
    var renderedShowsResidueColors = true

    private var alignmentVersion = 0
    private var parseTask: Task<Void, Never>?
    private var renderTask: Task<Void, Never>?
    private var cachedRenderVersion = -1
    private var cachedRenderFontSize = -1.0
    private var cachedRenderIdentityMode = false
    private var cachedPlainAlignment: RenderedAlignment?
    private var cachedColoredAlignment: RenderedAlignment?
    private var cachedConsensusKey: ConsensusKey?
    private var cachedConsensus: String = ""
    private var cachedAuxiliaryKey: AuxiliaryKey?
    private var cachedAuxiliaryContent: AuxiliaryPanelContent = .empty

    func parseAndRender(
        rawText: String,
        fontSize: Double,
        showsResidueColors: Bool,
        needsIdentityByColumn: Bool,
        referenceName: String?
    ) {
        parseTask?.cancel()
        renderTask?.cancel()

        guard !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            alignment = .empty
            renderedAlignment = .empty
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
                        showsResidueColors: showsResidueColors,
                        needsIdentityByColumn: needsIdentityByColumn,
                        referenceName: referenceName
                    )
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    alignment = .empty
                    renderedAlignment = .empty
                    parseErrorMessage = error.localizedDescription
                    clearCache()
                    contentVersion += 1
                }
            }
        }
    }

    func rerender(
        fontSize: Double,
        showsResidueColors: Bool,
        needsIdentityByColumn: Bool,
        referenceName: String?
    ) {
        renderTask?.cancel()

        let cacheKeyMatches =
            cachedRenderVersion == alignmentVersion &&
            abs(cachedRenderFontSize - fontSize) < 0.001 &&
            cachedRenderIdentityMode == needsIdentityByColumn

        if !cacheKeyMatches {
            cachedRenderVersion = alignmentVersion
            cachedRenderFontSize = fontSize
            cachedRenderIdentityMode = needsIdentityByColumn
            cachedPlainAlignment = nil
            cachedColoredAlignment = nil
        }

        if showsResidueColors, let colored = cachedColoredAlignment {
            apply(colored, showsResidueColors: true)
            return
        }
        if !showsResidueColors, let plain = cachedPlainAlignment {
            apply(plain, showsResidueColors: false)
            return
        }

        let displayAlignment = AlignmentData(
            format: alignment.format,
            rows: rowsExcludingReference(referenceName),
            length: alignment.length,
            sequenceKind: alignment.sequenceKind
        )
        let currentVersion = alignmentVersion

        renderTask = Task(priority: .userInitiated) {
            let rendered: RenderedAlignment = await runOnBackground {
                AlignmentRenderer.render(
                    displayAlignment,
                    showsResidueColors: showsResidueColors,
                    needsIdentityByColumn: needsIdentityByColumn,
                    fontSize: fontSize
                )
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard currentVersion == alignmentVersion else { return }
                if showsResidueColors {
                    cachedColoredAlignment = rendered
                } else {
                    cachedPlainAlignment = rendered
                }
                apply(rendered, showsResidueColors: showsResidueColors)
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

        let rows = rowsExcludingReference(referenceName)
        let referenceText = showsReferencePanel ? (row(named: referenceName)?.sequence ?? "") : nil
        let consensus = showsConsensusPanel ? cachedConsensusSequence(referenceName: referenceName, rows: rows) : nil
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

    func rowsExcludingReference(_ referenceName: String?) -> [AlignmentRow] {
        guard let referenceName else { return alignment.rows }
        var removed = false
        return alignment.rows.filter { row in
            if !removed, row.name == referenceName {
                removed = true
                return false
            }
            return true
        }
    }

    func containsRow(named name: String?) -> Bool {
        guard let name else { return false }
        return alignment.rows.contains(where: { $0.name == name })
    }

    private func apply(_ rendered: RenderedAlignment, showsResidueColors: Bool) {
        renderedAlignment = rendered
        renderedShowsResidueColors = showsResidueColors
        contentVersion += 1
    }

    private func clearCache() {
        cachedPlainAlignment = nil
        cachedColoredAlignment = nil
        cachedRenderVersion = -1
        cachedRenderFontSize = -1.0
        cachedRenderIdentityMode = false
        cachedConsensusKey = nil
        cachedConsensus = ""
        cachedAuxiliaryKey = nil
        cachedAuxiliaryContent = .empty
    }

    private func cachedConsensusSequence(referenceName: String?, rows: [AlignmentRow]) -> String {
        let key = ConsensusKey(alignmentVersion: alignmentVersion, referenceName: referenceName ?? "")
        if key == cachedConsensusKey {
            return cachedConsensus
        }
        let sequence = AlignmentStatistics.consensusSequence(rows: rows, length: alignment.length)
        cachedConsensusKey = key
        cachedConsensus = sequence
        return sequence
    }

    private func runOnBackground<T>(_ work: @escaping () -> T) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: work())
            }
        }
    }

    private func runOnBackgroundThrowing<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try work())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private struct ConsensusKey: Equatable {
        let alignmentVersion: Int
        let referenceName: String
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

private struct RootView: View {
    private enum ViewerMode: String, CaseIterable, Identifiable {
        case view = "View"
        case edit = "Edit"

        var id: String { rawValue }
    }

    @ObservedObject var document: ApuSeqDocument
    @Environment(\.documentConfiguration) private var documentConfiguration

    @State private var model = AlignmentViewModel()

    @AppStorage("alignmentFontSize") private var alignmentFontSize = 12.0
    @AppStorage("identityColorThreshold") private var identityColorThreshold = 0.5
    @State private var showsResidueColors = true
    @State private var showsIdentityShading = false
    @State private var showsInspector = false
    @State private var selectedResidueCount = 0
    @State private var selectedStartPosition: Int?
    @State private var selectedEndPosition: Int?

    @AppStorage("showReferencePanel") private var showsReferencePanel = false
    @AppStorage("showConsensusPanel") private var showsConsensusPanel = false
    @AppStorage("showConservationPanel") private var showsConservationPanel = false

    @State private var selectedReferenceName: String?
    @State private var viewerMode: ViewerMode = .view

    private var needsIdentityByColumn: Bool {
        showsIdentityShading || showsConservationPanel
    }

    private var displayRows: [AlignmentRow] {
        model.rowsExcludingReference(selectedReferenceName)
    }

    private var displayAlignment: AlignmentData {
        AlignmentData(
            format: model.alignment.format,
            rows: displayRows,
            length: model.alignment.length,
            sequenceKind: model.alignment.sequenceKind
        )
    }

    private var auxiliaryPanel: AuxiliaryPanelContent {
        model.auxiliaryPanelContent(
            referenceName: selectedReferenceName,
            showsReferencePanel: showsReferencePanel,
            showsConsensusPanel: showsConsensusPanel,
            showsConservationPanel: showsConservationPanel
        )
    }

    private var documentTitle: String {
        if let fileURL = documentConfiguration?.fileURL {
            return fileURL.lastPathComponent
        }
        if let suggested = document.suggestedSaveFilename, !suggested.isEmpty {
            return suggested
        }
        return "Untitled"
    }

    private var translationContext: TranslationContext {
        let baseName = documentConfiguration?.fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
        return TranslationContext(
            rawText: document.rawText,
            sequenceKind: model.alignment.sequenceKind,
            fileBaseName: baseName,
            sourceDirectoryURL: documentConfiguration?.fileURL?.deletingLastPathComponent()
        )
    }

    private func auxiliaryAttributedText(_ text: String) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: alignmentFontSize, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
    }

    var body: some View {
        Group {
            if let parseErrorMessage = model.parseErrorMessage {
                ContentUnavailableView(
                    "Cannot Parse Alignment",
                    systemImage: "exclamationmark.triangle",
                    description: Text(parseErrorMessage)
                )
            } else if model.alignment.rows.isEmpty {
                ContentUnavailableView(
                    "Open an Alignment",
                    systemImage: "doc.text",
                    description: Text("Supported formats: FASTA, CLUSTAL, plain text")
                )
            } else {
                VStack(spacing: 0) {
                    AlignmentTextView(
                        nameAttributedText: model.renderedAlignment.nameAttributedText,
                        sequenceAttributedText: model.renderedAlignment.sequenceAttributedText,
                        namesChecksum: model.renderedAlignment.namesChecksum,
                        sequenceChecksum: model.renderedAlignment.sequenceChecksum,
                        alignmentLength: displayAlignment.length,
                        identityByColumn: model.renderedAlignment.identityByColumn,
                        showsIdentityShading: showsIdentityShading,
                        identityColorThreshold: identityColorThreshold,
                        renderedShowsResidueColors: model.renderedShowsResidueColors,
                        fontSize: alignmentFontSize,
                        contentVersion: model.contentVersion,
                        defaultNameColumnWidth: model.renderedAlignment.nameColumnWidth,
                        displayedRowNames: displayRows.map(\.name),
                        auxiliaryNameAttributedText: auxiliaryAttributedText(auxiliaryPanel.leftText),
                        auxiliarySequenceAttributedText: auxiliaryAttributedText(auxiliaryPanel.rightText),
                        auxiliaryLineCount: auxiliaryPanel.lineCount,
                        preferredUnsavedFilename: documentConfiguration?.fileURL == nil ? document.suggestedSaveFilename : nil,
                        isEditMode: viewerMode == .edit,
                        onSequenceEdited: applyEditedSequenceText,
                        selectedResidueCount: $selectedResidueCount,
                        selectedStartPosition: $selectedStartPosition,
                        selectedEndPosition: $selectedEndPosition
                    ) { selectedName in
                        selectedReferenceName = selectedName
                        if selectedName != nil {
                            showsReferencePanel = true
                        }
                        rerender()
                    }
                    Divider()
                    FooterBar(
                        sequenceCount: displayAlignment.rows.count,
                        residueCount: displayAlignment.length,
                        sequenceKind: displayAlignment.sequenceKind,
                        selectedResidueCount: selectedResidueCount,
                        selectedStartPosition: selectedStartPosition,
                        selectedEndPosition: selectedEndPosition,
                        showsResidueColors: $showsResidueColors,
                        showsIdentityShading: $showsIdentityShading
                    )
                }
            }
        }
        .navigationTitle(documentTitle)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Picker("Mode", selection: $viewerMode) {
                    ForEach(ViewerMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .help("Switch between read-only view and edit mode")

                Button {
                    showsInspector.toggle()
                } label: {
                    Image(systemName: "info.circle")
                }
                .help("Show alignment information")
            }
        }
        .inspector(isPresented: $showsInspector) {
            FileInformationView(
                format: model.alignment.format.rawValue,
                sequenceCount: displayAlignment.rows.count,
                residueCount: displayAlignment.length,
                sourceCharacterCount: document.rawText.count
            )
        }
        .onAppear {
            markTranslatedDocumentAsEditedIfNeeded()
            parseAndRender()
        }
        .onChange(of: document.rawText) { _, _ in parseAndRender() }
        .onChange(of: showsResidueColors) { _, _ in rerender() }
        .onChange(of: showsIdentityShading) { _, _ in rerender() }
        .onChange(of: showsConservationPanel) { _, _ in rerender() }
        .onChange(of: alignmentFontSize) { _, _ in rerender() }
        .onChange(of: identityColorThreshold) { _, _ in rerender() }
        .focusedSceneValue(\.translationContext, translationContext)
    }

    private func parseAndRender() {
        if selectedReferenceName != nil, !model.containsRow(named: selectedReferenceName) {
            selectedReferenceName = nil
        }
        model.parseAndRender(
            rawText: document.rawText,
            fontSize: alignmentFontSize,
            showsResidueColors: showsResidueColors,
            needsIdentityByColumn: needsIdentityByColumn,
            referenceName: selectedReferenceName
        )
    }

    private func rerender() {
        model.rerender(
            fontSize: alignmentFontSize,
            showsResidueColors: showsResidueColors,
            needsIdentityByColumn: needsIdentityByColumn,
            referenceName: selectedReferenceName
        )
    }

    private func applyEditedSequenceText(_ editedText: String) {
        guard viewerMode == .edit else { return }
        guard let rebuilt = rebuildFASTA(fromEditedSequenceText: editedText) else { return }
        guard document.rawText != rebuilt else { return }
        document.rawText = rebuilt
    }

    private func rebuildFASTA(fromEditedSequenceText editedText: String) -> String? {
        let sequenceLines = editedText
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        guard sequenceLines.count == displayRows.count else { return nil }
        var output = ""
        output.reserveCapacity(editedText.count + (displayRows.count * 16))
        for (row, sequence) in zip(displayRows, sequenceLines) {
            output += ">"
            output += row.name
            output += "\n"
            output += sequence
            output += "\n"
        }
        return output
    }

    private func markTranslatedDocumentAsEditedIfNeeded() {
        guard documentConfiguration?.fileURL == nil else { return }
        guard document.markEditedOnFirstDisplay else { return }
        document.markEditedOnFirstDisplay = false
        document.rawText += "\n"
    }
}

private struct AuxiliaryPanelContent {
    let leftText: String
    let rightText: String
    let lineCount: Int

    static let empty = AuxiliaryPanelContent(leftText: "", rightText: "", lineCount: 0)
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

        if referenceSequence != nil {
            left.append(referenceLabel ?? "Ref:")
            right.append(referenceSequence ?? "")
        }
        if let consensusSequence {
            left.append("Consensus")
            right.append(consensusSequence)
        }
        if let conservation {
            left.append("Identity")
            right.append(conservationBars(from: conservation))
        }

        return AuxiliaryPanelContent(
            leftText: left.joined(separator: "\n"),
            rightText: right.joined(separator: "\n"),
            lineCount: max(left.count, right.count)
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

#Preview {
    ContentView(document: ApuSeqDocument())
}
