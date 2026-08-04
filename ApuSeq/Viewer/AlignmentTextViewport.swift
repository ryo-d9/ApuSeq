import AppKit
import SwiftUI

struct AlignmentTextViewport: NSViewRepresentable {
    let nameAttributedText: NSAttributedString
    let sequenceAttributedText: NSAttributedString
    let namesChecksum: UInt64
    let sequenceChecksum: UInt64
    let alignmentLength: Int
    let identityByColumn: [Double]
    let majorityResidueByColumn: [UInt16]
    let backgroundMode: AlignmentBackgroundMode
    let referenceSequenceForBackground: String?
    let identityColorThreshold: Double
    let fontSize: Double
    let contentVersion: Int
    let defaultNameColumnWidth: CGFloat
    let displayedRowNames: [String]
    let displayedRowSequences: [String]
    let highlightedNameRowIndex: Int?
    let nameSearchRequestID: Int
    let auxiliaryNameAttributedText: NSAttributedString
    let auxiliarySequenceAttributedText: NSAttributedString
    let auxiliaryLineCount: Int
    let isEditMode: Bool
    let canEditSequenceNames: Bool
    let onSequenceEdited: (String) -> Void
    @Binding var selectedResidueCount: Int
    @Binding var selectedSequenceCount: Int
    @Binding var selectedStartPosition: Int?
    @Binding var selectedEndPosition: Int?
    let onAddSequence: () -> Void
    let onAddFASTAFromClipboard: () -> Void
    let onRenameSequence: (Int) -> Void
    let onDeleteSequence: (Int) -> Void
    let onSetReference: (String?) -> Void

    func makeNSView(context: Context) -> AlignmentViewportContainerView {
        let nameColumnView = AlignmentViewportNameColumnView()
        nameColumnView.setAccessibilityIdentifier("alignment-name-column")
        nameColumnView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        nameColumnView.rowNames = displayedRowNames
        nameColumnView.highlightedRowIndex = highlightedNameRowIndex
        nameColumnView.isEditMode = isEditMode
        nameColumnView.canEditSequenceNames = canEditSequenceNames
        nameColumnView.onAddSequence = onAddSequence
        nameColumnView.onAddFASTAFromClipboard = onAddFASTAFromClipboard
        nameColumnView.onRenameSequence = onRenameSequence
        nameColumnView.onDeleteSequence = onDeleteSequence
        nameColumnView.onSetReference = onSetReference

        let sequenceTextView = AlignmentViewportSequenceTextView(usingTextLayoutManager: true)
        sequenceTextView.setAccessibilityIdentifier("alignment-sequence-text")
        configureMainTextView(sequenceTextView, fontSize: fontSize)
        sequenceTextView.delegate = context.coordinator
        sequenceTextView.onAddVerticalCursor = { [weak coordinator = context.coordinator, weak sequenceTextView] direction in
            guard let coordinator, let sequenceTextView else { return false }
            return coordinator.addVerticalCursors(in: sequenceTextView, direction: direction)
        }
        sequenceTextView.onAddSequence = onAddSequence
        sequenceTextView.canAddSequenceFromMenu = canEditSequenceNames

        let auxiliaryNameTextView = NSTextView(usingTextLayoutManager: true)
        auxiliaryNameTextView.setAccessibilityIdentifier("alignment-auxiliary-name-text")
        configureAuxiliaryTextView(auxiliaryNameTextView, fontSize: fontSize)

        let auxiliarySequenceTextView = NSTextView(usingTextLayoutManager: true)
        auxiliarySequenceTextView.setAccessibilityIdentifier("alignment-auxiliary-sequence-text")
        configureAuxiliaryTextView(auxiliarySequenceTextView, fontSize: fontSize)

        let containerView = AlignmentViewportContainerView(
            nameColumnView: nameColumnView,
            sequenceTextView: sequenceTextView,
            auxiliaryNameTextView: auxiliaryNameTextView,
            auxiliarySequenceTextView: auxiliarySequenceTextView
        )
        containerView.updateNameRows(
            displayedRowNames,
            sequences: displayedRowSequences,
            isEditMode: isEditMode,
            canEditSequenceNames: canEditSequenceNames,
            onAddSequence: onAddSequence,
            onAddFASTAFromClipboard: onAddFASTAFromClipboard,
            onRenameSequence: onRenameSequence,
            onDeleteSequence: onDeleteSequence,
            onSetReference: onSetReference
        )
        context.coordinator.installScrollSync(for: containerView)
        context.coordinator.lastNameSearchRequestID = nameSearchRequestID
        return containerView
    }

    func updateNSView(_ containerView: AlignmentViewportContainerView, context: Context) {
        containerView.updateNameColumnWidth(defaultNameColumnWidth)
        containerView.updateEditMode(isEditable: isEditMode)
        containerView.updateNameRows(
            displayedRowNames,
            sequences: displayedRowSequences,
            isEditMode: isEditMode,
            canEditSequenceNames: canEditSequenceNames,
            onAddSequence: onAddSequence,
            onAddFASTAFromClipboard: onAddFASTAFromClipboard,
            onRenameSequence: onRenameSequence,
            onDeleteSequence: onDeleteSequence,
            onSetReference: onSetReference
        )
        containerView.updateHighlightedNameRow(highlightedNameRowIndex)
        if context.coordinator.lastNameSearchRequestID != nameSearchRequestID {
            context.coordinator.lastNameSearchRequestID = nameSearchRequestID
            if let highlightedNameRowIndex {
                containerView.scrollNameRowToVisible(highlightedNameRowIndex)
            }
        }
        containerView.updateNameColumnVerticalOffset()
        containerView.updateAuxiliaryPanel(
            nameText: auxiliaryNameAttributedText,
            sequenceText: auxiliarySequenceAttributedText,
            lineCount: auxiliaryLineCount,
            fontSize: fontSize
        )
        context.coordinator.onSequenceEdited = onSequenceEdited
        context.coordinator.isProgrammaticTextUpdate = true

        let fingerprint = RenderedFingerprint(
            namesChecksum: namesChecksum,
            sequenceChecksum: sequenceChecksum,
            nameLength: nameAttributedText.length,
            sequenceLength: sequenceAttributedText.length
        )
        if context.coordinator.lastContentVersion != contentVersion ||
            context.coordinator.lastRenderedFingerprint != fingerprint {
            let previousAlignmentLength = containerView.sequenceTextView.alignmentLength
            let selectedRanges = context.coordinator.logicalRanges(
                from: containerView.sequenceTextView.selectedRanges.map(\.rangeValue),
                alignmentLength: previousAlignmentLength
            )
            let columnSelectionRanges = context.coordinator.logicalRanges(
                from: containerView.sequenceTextView.columnSelectionRanges,
                alignmentLength: previousAlignmentLength
            )
            let columnSelectionAnchor = context.coordinator.logicalLocation(
                from: containerView.sequenceTextView.columnSelectionAnchor,
                alignmentLength: previousAlignmentLength
            )
            let columnSelectionWidth = containerView.sequenceTextView.columnSelectionWidth
            containerView.nameColumnView.rowNames = displayedRowNames
            containerView.sequenceTextView.textStorage?.setAttributedString(sequenceAttributedText)
            containerView.sequenceTextView.alignmentLength = alignmentLength
            context.coordinator.restoreSelection(
                selectedRanges,
                columnSelectionRanges: columnSelectionRanges,
                columnSelectionAnchor: columnSelectionAnchor,
                columnSelectionWidth: columnSelectionWidth,
                in: containerView.sequenceTextView
            )
            context.coordinator.lastContentVersion = contentVersion
            context.coordinator.lastRenderedFingerprint = fingerprint
            DispatchQueue.main.async { [weak sequenceTextView = containerView.sequenceTextView, weak coordinator = context.coordinator] in
                guard let sequenceTextView, let coordinator else { return }
                coordinator.updateSelectedResidueCount(in: sequenceTextView)
            }
        }
        context.coordinator.isProgrammaticTextUpdate = false

        if context.coordinator.lastFontSize != fontSize {
            let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            containerView.nameColumnView.font = font
            containerView.sequenceTextView.font = font
            containerView.auxiliaryNameTextView.font = font
            containerView.auxiliarySequenceTextView.font = font
            containerView.rulerView.update(length: alignmentLength, font: font, textInset: containerView.sequenceTextView.textContainerInset.width)
            context.coordinator.lastFontSize = fontSize
        }

        containerView.sequenceTextView.updateAlignmentDisplay(
            alignmentLength: alignmentLength,
            identityByColumn: identityByColumn,
            majorityResidueByColumn: majorityResidueByColumn,
            backgroundMode: backgroundMode,
            referenceSequenceForBackground: referenceSequenceForBackground,
            identityColorThreshold: identityColorThreshold
        )
        containerView.rulerView.update(
            length: alignmentLength,
            font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
            textInset: containerView.sequenceTextView.textContainerInset.width
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            selectedResidueCount: $selectedResidueCount,
            selectedSequenceCount: $selectedSequenceCount,
            selectedStartPosition: $selectedStartPosition,
            selectedEndPosition: $selectedEndPosition
        )
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var lastContentVersion = -1
        var lastFontSize = -1.0
        var lastRenderedFingerprint = RenderedFingerprint.empty
        var lastNameSearchRequestID = -1
        var onSequenceEdited: ((String) -> Void)?
        var isProgrammaticTextUpdate = false

        private struct SelectionSummary: Equatable {
            let residueCount: Int
            let sequenceCount: Int
            let startPosition: Int?
            let endPosition: Int?
        }

        struct LogicalRange {
            let row: Int
            let column: Int
            let length: Int
        }

        struct LogicalLocation {
            let row: Int
            let column: Int
        }

        private let selectedResidueCount: Binding<Int>
        private let selectedSequenceCount: Binding<Int>
        private let selectedStartPosition: Binding<Int?>
        private let selectedEndPosition: Binding<Int?>
        private var observerTokens: [NSObjectProtocol] = []
        private var isSyncingScroll = false
        private var pendingSelectionSummary: SelectionSummary?
        private var isSelectionSummaryUpdateScheduled = false
        private var lastAppliedSelectionSummary: SelectionSummary?

        init(
            selectedResidueCount: Binding<Int>,
            selectedSequenceCount: Binding<Int>,
            selectedStartPosition: Binding<Int?>,
            selectedEndPosition: Binding<Int?>
        ) {
            self.selectedResidueCount = selectedResidueCount
            self.selectedSequenceCount = selectedSequenceCount
            self.selectedStartPosition = selectedStartPosition
            self.selectedEndPosition = selectedEndPosition
        }

        deinit {
            for token in observerTokens {
                NotificationCenter.default.removeObserver(token)
            }
        }

        func installScrollSync(for containerView: AlignmentViewportContainerView) {
            guard observerTokens.isEmpty else { return }
            containerView.sequenceScrollView.contentView.postsBoundsChangedNotifications = true
            containerView.auxiliarySequenceScrollView.contentView.postsBoundsChangedNotifications = true

            let sequenceToken = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: containerView.sequenceScrollView.contentView,
                queue: .main
            ) { [weak containerView] _ in
                guard let containerView else { return }
                containerView.handleSequenceBoundsChange()
            }

            let auxiliarySequenceToken = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: containerView.auxiliarySequenceScrollView.contentView,
                queue: .main
            ) { [weak self, weak containerView] _ in
                guard let self, let containerView else { return }
                self.syncHorizontalOffset(from: containerView.auxiliarySequenceScrollView, to: containerView.sequenceScrollView)
                containerView.rulerView.needsDisplay = true
            }

            observerTokens = [sequenceToken, auxiliarySequenceToken]
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if let sequenceView = textView as? AlignmentViewportSequenceTextView {
                let ranges = sequenceView.selectedRanges.map(\.rangeValue)
                if ranges.count > 1 {
                    sequenceView.columnSelectionRanges = ranges
                } else {
                    sequenceView.columnSelectionRanges = []
                    sequenceView.columnSelectionAnchor = nil
                }
            }
            updateSelectedResidueCount(in: textView)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            guard textView.isEditable else { return }
            guard !isProgrammaticTextUpdate else { return }
            onSequenceEdited?(textView.string)
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            guard let sequenceView = textView as? AlignmentViewportSequenceTextView else { return true }
            guard sequenceView.isEditable else { return true }
            let selectedRanges = sequenceView.columnSelectionRanges.count > 1
                ? sequenceView.columnSelectionRanges
                : [affectedCharRange]
            sequenceView.applyAlignmentReplacement(replacementString ?? "", to: selectedRanges)
            return false
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextInRanges affectedRanges: [NSValue],
            replacementStrings: [String]?
        ) -> Bool {
            guard let sequenceView = textView as? AlignmentViewportSequenceTextView else { return true }
            guard sequenceView.isEditable else { return true }
            let selectedRanges = sequenceView.columnSelectionRanges.count > 1
                ? sequenceView.columnSelectionRanges
                : affectedRanges.map(\.rangeValue)
            sequenceView.applyAlignmentReplacement(
                replacementStrings?.first ?? "",
                to: selectedRanges
            )
            return false
        }

        func addVerticalCursors(in textView: AlignmentViewportSequenceTextView, direction: Int) -> Bool {
            guard direction == -1 || direction == 1 else { return false }
            let lineSpan = textView.alignmentLength + 1
            guard lineSpan > 1 else { return false }
            let text = textView.string as NSString
            let textLength = text.length
            guard textLength > 0 else { return false }

            let currentRanges = textView.selectedRanges.map(\.rangeValue)
            guard !currentRanges.isEmpty else { return false }

            let anchorLocation: Int
            let baseWidth: Int
            if currentRanges.count <= 1 {
                let selection = textView.selectedRange()
                anchorLocation = selection.location
                baseWidth = max(selection.length, 1)
                textView.columnSelectionAnchor = anchorLocation
                textView.columnSelectionWidth = baseWidth
            } else if let savedAnchor = textView.columnSelectionAnchor {
                anchorLocation = savedAnchor
                baseWidth = max(textView.columnSelectionWidth, 1)
            } else {
                let selection = textView.selectedRange()
                anchorLocation = selection.location
                baseWidth = max(selection.length, 1)
                textView.columnSelectionAnchor = anchorLocation
                textView.columnSelectionWidth = baseWidth
            }
            guard anchorLocation >= 0, anchorLocation < textLength else { return false }

            let anchorColumn = anchorLocation % lineSpan
            let clampedWidth = min(baseWidth, max(textView.alignmentLength - anchorColumn, 1))

            let normalizedRanges: [NSRange] = currentRanges.compactMap { range in
                let location = range.location
                guard location >= 0, location < textLength else { return nil }
                guard text.character(at: location) != 10 else { return nil }
                return NSRange(location: location, length: clampedWidth)
            }

            var minDelta = 0
            var maxDelta = 0
            for range in normalizedRanges {
                let deltaLocation = range.location - anchorLocation
                guard deltaLocation % lineSpan == 0 else { continue }
                let delta = deltaLocation / lineSpan
                minDelta = min(minDelta, delta)
                maxDelta = max(maxDelta, delta)
            }

            let nextDelta = (direction < 0) ? (minDelta - 1) : (maxDelta + 1)
            let target = anchorLocation + (nextDelta * lineSpan)
            guard target >= 0, target < textLength else { return false }
            guard text.character(at: target) != 10 else { return false }
            if normalizedRanges.contains(where: { $0.location == target && $0.length == clampedWidth }) {
                return false
            }

            var mergedRanges = normalizedRanges
            mergedRanges.append(NSRange(location: target, length: clampedWidth))

            let anchorRange = NSRange(location: anchorLocation, length: clampedWidth)
            let otherRanges = mergedRanges
                .filter { !NSEqualRanges($0, anchorRange) }
                .sorted { lhs, rhs in
                    if lhs.location == rhs.location { return lhs.length < rhs.length }
                    return lhs.location < rhs.location
                }
            let finalRanges = [anchorRange] + otherRanges

            textView.setSelectedRanges(
                finalRanges.map(NSValue.init(range:)),
                affinity: .downstream,
                stillSelecting: false
            )
            textView.columnSelectionRanges = finalRanges
            return true
        }

        func updateSelectedResidueCount(in textView: NSTextView) {
            let alignmentLength = (textView as? AlignmentViewportSequenceTextView)?.alignmentLength ?? 0
            guard alignmentLength > 0 else {
                scheduleSelectionSummaryUpdate(
                    SelectionSummary(
                        residueCount: 0,
                        sequenceCount: 0,
                        startPosition: nil,
                        endPosition: nil
                    )
                )
                return
            }

            let lineSpan = alignmentLength + 1
            var count = 0
            var selectedRows = Set<Int>()
            var minPosition: Int?
            var maxPosition: Int?

            for rangeValue in textView.selectedRanges {
                let range = rangeValue.rangeValue
                guard range.length > 0 else { continue }
                let upperBound = NSMaxRange(range)
                var location = range.location
                while location < upperBound {
                    let row = location / lineSpan
                    let column = location % lineSpan
                    if column < alignmentLength {
                        count += 1
                        selectedRows.insert(row)
                        let position = column + 1
                        minPosition = minPosition.map { min($0, position) } ?? position
                        maxPosition = maxPosition.map { max($0, position) } ?? position
                    }
                    location += 1
                }
            }

            scheduleSelectionSummaryUpdate(
                SelectionSummary(
                    residueCount: count,
                    sequenceCount: selectedRows.count,
                    startPosition: minPosition,
                    endPosition: maxPosition
                )
            )
        }

        private func scheduleSelectionSummaryUpdate(_ summary: SelectionSummary) {
            guard summary != lastAppliedSelectionSummary || pendingSelectionSummary != nil else { return }
            pendingSelectionSummary = summary
            guard !isSelectionSummaryUpdateScheduled else { return }

            isSelectionSummaryUpdateScheduled = true
            DispatchQueue.main.async { [weak self] in
                self?.flushPendingSelectionSummary()
            }
        }

        private func flushPendingSelectionSummary() {
            isSelectionSummaryUpdateScheduled = false
            guard let summary = pendingSelectionSummary else { return }
            pendingSelectionSummary = nil
            guard summary != lastAppliedSelectionSummary else { return }

            selectedResidueCount.wrappedValue = summary.residueCount
            selectedSequenceCount.wrappedValue = summary.sequenceCount
            selectedStartPosition.wrappedValue = summary.startPosition
            selectedEndPosition.wrappedValue = summary.endPosition
            lastAppliedSelectionSummary = summary
        }

        func logicalRanges(from ranges: [NSRange], alignmentLength: Int) -> [LogicalRange] {
            guard alignmentLength >= 0 else { return [] }
            let lineSpan = alignmentLength + 1
            guard lineSpan > 0 else { return [] }
            return ranges.compactMap { range in
                guard range.location != NSNotFound, range.location >= 0 else { return nil }
                let row = range.location / lineSpan
                let column = min(range.location % lineSpan, alignmentLength)
                let length = min(max(range.length, 0), max(alignmentLength - column, 0))
                return LogicalRange(row: row, column: column, length: length)
            }
        }

        func logicalLocation(from location: Int?, alignmentLength: Int) -> LogicalLocation? {
            guard let location, location != NSNotFound, location >= 0 else { return nil }
            let lineSpan = alignmentLength + 1
            guard lineSpan > 0 else { return nil }
            return LogicalLocation(
                row: location / lineSpan,
                column: min(location % lineSpan, alignmentLength)
            )
        }

        func restoreSelection(
            _ selectedRanges: [LogicalRange],
            columnSelectionRanges: [LogicalRange],
            columnSelectionAnchor: LogicalLocation?,
            columnSelectionWidth: Int,
            in textView: AlignmentViewportSequenceTextView
        ) {
            let textLength = (textView.string as NSString).length
            let restoredRanges = selectedRanges.compactMap {
                range(from: $0, alignmentLength: textView.alignmentLength, textLength: textLength)
            }
            guard !restoredRanges.isEmpty else { return }

            textView.setSelectedRanges(
                restoredRanges.map(NSValue.init(range:)),
                affinity: .downstream,
                stillSelecting: false
            )
            textView.columnSelectionRanges = columnSelectionRanges.compactMap {
                range(from: $0, alignmentLength: textView.alignmentLength, textLength: textLength)
            }
            textView.columnSelectionAnchor = columnSelectionAnchor.flatMap {
                location(from: $0, alignmentLength: textView.alignmentLength, textLength: textLength)
            }
            textView.columnSelectionWidth = columnSelectionWidth
        }

        private func range(from logicalRange: LogicalRange, alignmentLength: Int, textLength: Int) -> NSRange? {
            guard logicalRange.row >= 0, logicalRange.column >= 0 else { return nil }
            let lineSpan = alignmentLength + 1
            let location = logicalRange.row * lineSpan + min(logicalRange.column, alignmentLength)
            guard location <= textLength else { return nil }
            let length = min(logicalRange.length, max(alignmentLength - logicalRange.column, 0))
            return NSRange(location: location, length: min(length, max(textLength - location, 0)))
        }

        private func location(from logicalLocation: LogicalLocation, alignmentLength: Int, textLength: Int) -> Int? {
            guard logicalLocation.row >= 0, logicalLocation.column >= 0 else { return nil }
            let lineSpan = alignmentLength + 1
            let location = logicalLocation.row * lineSpan + min(logicalLocation.column, alignmentLength)
            guard location <= textLength else { return nil }
            return location
        }


        private func syncHorizontalOffset(from source: NSScrollView, to destination: NSScrollView) {
            guard !isSyncingScroll else { return }
            let sourceX = source.contentView.bounds.origin.x
            var destinationOrigin = destination.contentView.bounds.origin
            guard abs(destinationOrigin.x - sourceX) > 0.5 else { return }
            isSyncingScroll = true
            destinationOrigin.x = sourceX
            destination.contentView.scroll(to: destinationOrigin)
            destination.reflectScrolledClipView(destination.contentView)
            isSyncingScroll = false
        }
    }
}
