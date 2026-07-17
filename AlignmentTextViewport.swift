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
    let identityColorThreshold: Double
    let fontSize: Double
    let contentVersion: Int
    let defaultNameColumnWidth: CGFloat
    let displayedRowNames: [String]
    let auxiliaryNameAttributedText: NSAttributedString
    let auxiliarySequenceAttributedText: NSAttributedString
    let auxiliaryLineCount: Int
    let isEditMode: Bool
    let onSequenceEdited: (String) -> Void
    @Binding var selectedResidueCount: Int
    @Binding var selectedStartPosition: Int?
    @Binding var selectedEndPosition: Int?
    let onDeleteSequence: (Int) -> Void
    let onSetReference: (String?) -> Void

    func makeNSView(context: Context) -> AlignmentViewportContainerView {
        let nameColumnView = AlignmentViewportNameColumnView()
        nameColumnView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        nameColumnView.rowNames = displayedRowNames
        nameColumnView.isEditMode = isEditMode
        nameColumnView.onDeleteSequence = onDeleteSequence
        nameColumnView.onSetReference = onSetReference

        let sequenceTextView = AlignmentViewportSequenceTextView(usingTextLayoutManager: true)
        configureMainTextView(sequenceTextView, fontSize: fontSize)
        sequenceTextView.delegate = context.coordinator
        sequenceTextView.onAddVerticalCursor = { [weak coordinator = context.coordinator, weak sequenceTextView] direction in
            guard let coordinator, let sequenceTextView else { return false }
            return coordinator.addVerticalCursors(in: sequenceTextView, direction: direction)
        }

        let auxiliaryNameColumnView = AlignmentViewportNameColumnView()
        auxiliaryNameColumnView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)

        let auxiliarySequenceTextView = NSTextView(usingTextLayoutManager: true)
        configureAuxiliaryTextView(auxiliarySequenceTextView, fontSize: fontSize)

        let containerView = AlignmentViewportContainerView(
            nameColumnView: nameColumnView,
            sequenceTextView: sequenceTextView,
            auxiliaryNameColumnView: auxiliaryNameColumnView,
            auxiliarySequenceTextView: auxiliarySequenceTextView
        )
        containerView.updateNameRows(
            displayedRowNames,
            isEditMode: isEditMode,
            onDeleteSequence: onDeleteSequence,
            onSetReference: onSetReference
        )
        context.coordinator.installScrollSync(for: containerView)
        return containerView
    }

    func updateNSView(_ containerView: AlignmentViewportContainerView, context: Context) {
        containerView.updateNameColumnWidth(defaultNameColumnWidth)
        containerView.updateEditMode(isEditable: isEditMode)
        containerView.updateNameRows(
            displayedRowNames,
            isEditMode: isEditMode,
            onDeleteSequence: onDeleteSequence,
            onSetReference: onSetReference
        )
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
            containerView.nameColumnView.rowNames = displayedRowNames
            containerView.sequenceTextView.textStorage?.setAttributedString(sequenceAttributedText)
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
            containerView.auxiliaryNameColumnView.font = font
            containerView.auxiliarySequenceTextView.font = font
            containerView.rulerView.update(length: alignmentLength, font: font, textInset: containerView.sequenceTextView.textContainerInset.width)
            context.coordinator.lastFontSize = fontSize
        }

        containerView.sequenceTextView.updateAlignmentDisplay(
            alignmentLength: alignmentLength,
            identityByColumn: identityByColumn,
            majorityResidueByColumn: majorityResidueByColumn,
            backgroundMode: backgroundMode,
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
            selectedStartPosition: $selectedStartPosition,
            selectedEndPosition: $selectedEndPosition
        )
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var lastContentVersion = -1
        var lastFontSize = -1.0
        var lastRenderedFingerprint = RenderedFingerprint.empty
        var onSequenceEdited: ((String) -> Void)?
        var isProgrammaticTextUpdate = false

        private let selectedResidueCount: Binding<Int>
        private let selectedStartPosition: Binding<Int?>
        private let selectedEndPosition: Binding<Int?>
        private var observerTokens: [NSObjectProtocol] = []
        private var isSyncingScroll = false

        init(
            selectedResidueCount: Binding<Int>,
            selectedStartPosition: Binding<Int?>,
            selectedEndPosition: Binding<Int?>
        ) {
            self.selectedResidueCount = selectedResidueCount
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
            let selectedRanges = sequenceView.columnSelectionRanges.isEmpty
                ? sequenceView.selectedRanges.map(\.rangeValue)
                : sequenceView.columnSelectionRanges
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
            sequenceView.applyAlignmentReplacement(
                replacementStrings?.first ?? "",
                to: affectedRanges.map(\.rangeValue)
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
                selectedResidueCount.wrappedValue = 0
                selectedStartPosition.wrappedValue = nil
                selectedEndPosition.wrappedValue = nil
                return
            }

            let lineSpan = alignmentLength + 1
            var count = 0
            var minPosition: Int?
            var maxPosition: Int?

            for rangeValue in textView.selectedRanges {
                let range = rangeValue.rangeValue
                guard range.length > 0 else { continue }
                let upperBound = NSMaxRange(range)
                var location = range.location
                while location < upperBound {
                    let column = location % lineSpan
                    if column < alignmentLength {
                        count += 1
                        let position = column + 1
                        minPosition = minPosition.map { min($0, position) } ?? position
                        maxPosition = maxPosition.map { max($0, position) } ?? position
                    }
                    location += 1
                }
            }

            selectedResidueCount.wrappedValue = count
            selectedStartPosition.wrappedValue = minPosition
            selectedEndPosition.wrappedValue = maxPosition
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

final class AlignmentViewportContainerView: NSView, NSSplitViewDelegate {
    private static let minimumNameWidth: CGFloat = 90
    private static let minimumSequenceWidth: CGFloat = 160
    private static let splitViewAutosaveName = NSSplitView.AutosaveName("ApuSeqAlignmentViewportSplitView")

    let nameColumnView: AlignmentViewportNameColumnView
    let sequenceScrollView: NSScrollView
    let auxiliaryNameColumnView: AlignmentViewportNameColumnView
    let auxiliarySequenceScrollView: NSScrollView
    let sequenceTextView: AlignmentViewportSequenceTextView
    let auxiliarySequenceTextView: NSTextView
    let rulerView: AlignmentViewportRulerView

    private let splitView: NSSplitView
    private let leftPane = NSView()
    private let rightPane = NSView()
    private let leftStack = NSStackView()
    private let rightStack = NSStackView()
    private let leftHeaderSpacer = NSView()
    private var leftAuxHeightConstraint: NSLayoutConstraint?
    private var rightAuxHeightConstraint: NSLayoutConstraint?
    private var desiredNameWidth: CGFloat = 180
    private var hasInitializedNameWidth = false
    private var lastSequenceHorizontalOffset = CGFloat.greatestFiniteMagnitude

    init(
        nameColumnView: AlignmentViewportNameColumnView,
        sequenceTextView: AlignmentViewportSequenceTextView,
        auxiliaryNameColumnView: AlignmentViewportNameColumnView,
        auxiliarySequenceTextView: NSTextView
    ) {
        self.nameColumnView = nameColumnView
        self.sequenceTextView = sequenceTextView
        self.auxiliaryNameColumnView = auxiliaryNameColumnView
        self.auxiliarySequenceTextView = auxiliarySequenceTextView

        sequenceScrollView = NSScrollView()
        sequenceScrollView.documentView = sequenceTextView
        sequenceScrollView.hasVerticalScroller = true
        sequenceScrollView.hasHorizontalScroller = true
        sequenceScrollView.autohidesScrollers = true
        sequenceScrollView.borderType = .noBorder

        auxiliarySequenceScrollView = NSScrollView()
        auxiliarySequenceScrollView.documentView = auxiliarySequenceTextView
        auxiliarySequenceScrollView.hasVerticalScroller = false
        auxiliarySequenceScrollView.hasHorizontalScroller = true
        auxiliarySequenceScrollView.autohidesScrollers = true
        auxiliarySequenceScrollView.borderType = .noBorder

        rulerView = AlignmentViewportRulerView(scrollView: sequenceScrollView)

        splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.autosaveName = Self.splitViewAutosaveName

        super.init(frame: .zero)
        splitView.delegate = self
        setupLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func updateEditMode(isEditable: Bool) {
        sequenceTextView.isEditable = isEditable
        sequenceTextView.isSelectable = true
    }

    func updateNameRows(
        _ names: [String],
        isEditMode: Bool,
        onDeleteSequence: @escaping (Int) -> Void,
        onSetReference: @escaping (String?) -> Void
    ) {
        if nameColumnView.rowNames != names {
            nameColumnView.rowNames = names
        }
        nameColumnView.isEditMode = isEditMode
        nameColumnView.onDeleteSequence = onDeleteSequence
        nameColumnView.onSetReference = onSetReference
    }

    func updateAuxiliaryPanel(
        nameText: NSAttributedString,
        sequenceText: NSAttributedString,
        lineCount: Int,
        fontSize: Double
    ) {
        auxiliaryNameColumnView.rowNames = nameText.string
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        auxiliarySequenceTextView.textStorage?.setAttributedString(sequenceText)

        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let lineHeight = max(ceil(font.ascender - font.descender + font.leading), 1)
        let height = lineCount > 0 ? max(CGFloat(lineCount) * lineHeight + 8, 24) : 0
        let isVisible = lineCount > 0
        leftAuxHeightConstraint?.constant = height
        rightAuxHeightConstraint?.constant = height
        auxiliaryNameColumnView.isHidden = !isVisible
        auxiliarySequenceScrollView.isHidden = !isVisible
        sequenceScrollView.hasHorizontalScroller = !isVisible
        auxiliarySequenceScrollView.hasHorizontalScroller = isVisible
        syncAuxiliaryHorizontalOffset()
    }

    func updateNameColumnWidth(_ width: CGFloat) {
        if !hasInitializedNameWidth {
            hasInitializedNameWidth = true
            desiredNameWidth = max(width, Self.minimumNameWidth)
            applySplitPosition()
        }
    }

    override func layout() {
        super.layout()
        applySplitPosition()
        updateNameColumnVerticalOffset()
        syncAuxiliaryHorizontalOffset()
    }

    func updateNameColumnVerticalOffset() {
        nameColumnView.verticalOffset = sequenceScrollView.contentView.bounds.origin.y
    }

    func handleSequenceBoundsChange() {
        let origin = sequenceScrollView.contentView.bounds.origin
        updateNameColumnVerticalOffset()
        guard abs(origin.x - lastSequenceHorizontalOffset) > 0.5 else { return }
        lastSequenceHorizontalOffset = origin.x
        syncAuxiliaryHorizontalOffset()
        rulerView.needsDisplay = true
    }

    func syncAuxiliaryHorizontalOffset() {
        let sequenceX = sequenceScrollView.contentView.bounds.origin.x
        var auxiliaryOrigin = auxiliarySequenceScrollView.contentView.bounds.origin
        if abs(auxiliaryOrigin.x - sequenceX) > 0.5 {
            auxiliaryOrigin.x = sequenceX
            auxiliarySequenceScrollView.contentView.scroll(to: auxiliaryOrigin)
            auxiliarySequenceScrollView.reflectScrolledClipView(auxiliarySequenceScrollView.contentView)
        }

    }

    private func setupLayout() {
        [
            splitView, leftPane, rightPane, leftStack, rightStack, leftHeaderSpacer,
            nameColumnView, sequenceScrollView, auxiliaryNameColumnView, auxiliarySequenceScrollView, rulerView
        ].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }

        addSubview(splitView)
        splitView.addArrangedSubview(leftPane)
        splitView.addArrangedSubview(rightPane)

        leftPane.addSubview(leftStack)
        rightPane.addSubview(rightStack)

        leftStack.orientation = .vertical
        leftStack.spacing = 0
        leftStack.addArrangedSubview(leftHeaderSpacer)
        leftStack.addArrangedSubview(nameColumnView)
        leftStack.addArrangedSubview(auxiliaryNameColumnView)

        rightStack.orientation = .vertical
        rightStack.spacing = 0
        rightStack.addArrangedSubview(rulerView)
        rightStack.addArrangedSubview(sequenceScrollView)
        rightStack.addArrangedSubview(auxiliarySequenceScrollView)

        leftAuxHeightConstraint = auxiliaryNameColumnView.heightAnchor.constraint(equalToConstant: 0)
        rightAuxHeightConstraint = auxiliarySequenceScrollView.heightAnchor.constraint(equalToConstant: 0)
        leftAuxHeightConstraint?.isActive = true
        rightAuxHeightConstraint?.isActive = true
        auxiliaryNameColumnView.isHidden = true
        auxiliarySequenceScrollView.isHidden = true

        NSLayoutConstraint.activate([
            splitView.leadingAnchor.constraint(equalTo: leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: trailingAnchor),
            splitView.topAnchor.constraint(equalTo: topAnchor),
            splitView.bottomAnchor.constraint(equalTo: bottomAnchor),

            leftStack.leadingAnchor.constraint(equalTo: leftPane.leadingAnchor),
            leftStack.trailingAnchor.constraint(equalTo: leftPane.trailingAnchor),
            leftStack.topAnchor.constraint(equalTo: leftPane.topAnchor),
            leftStack.bottomAnchor.constraint(equalTo: leftPane.bottomAnchor),

            rightStack.leadingAnchor.constraint(equalTo: rightPane.leadingAnchor),
            rightStack.trailingAnchor.constraint(equalTo: rightPane.trailingAnchor),
            rightStack.topAnchor.constraint(equalTo: rightPane.topAnchor),
            rightStack.bottomAnchor.constraint(equalTo: rightPane.bottomAnchor),

            leftHeaderSpacer.heightAnchor.constraint(equalToConstant: AlignmentViewportRulerView.rulerHeight),
            rulerView.heightAnchor.constraint(equalToConstant: AlignmentViewportRulerView.rulerHeight)
        ])
    }

    private func applySplitPosition() {
        guard splitView.subviews.count >= 2 else { return }
        let maxAllowed = max(Self.minimumNameWidth, bounds.width - splitView.dividerThickness - Self.minimumSequenceWidth)
        let clamped = min(max(desiredNameWidth, Self.minimumNameWidth), maxAllowed)
        if abs(splitView.subviews[0].frame.width - clamped) > 0.5 {
            splitView.setPosition(clamped, ofDividerAt: 0)
        }
    }

    func splitView(_ splitView: NSSplitView, constrainSplitPosition proposedPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        let maxAllowed = max(Self.minimumNameWidth, bounds.width - splitView.dividerThickness - Self.minimumSequenceWidth)
        return min(max(proposedPosition, Self.minimumNameWidth), maxAllowed)
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard splitView.subviews.count >= 2 else { return }
        desiredNameWidth = splitView.subviews[0].frame.width
        rulerView.needsDisplay = true
    }

    func splitView(_ splitView: NSSplitView, shouldAdjustSizeOfSubview view: NSView) -> Bool {
        view !== leftPane
    }
}

final class AlignmentViewportNameColumnView: NSView {
    var rowNames: [String] = [] {
        didSet { needsDisplay = true }
    }
    var verticalOffset: CGFloat = 0 {
        didSet {
            if abs(verticalOffset - oldValue) > 0.5 {
                needsDisplay = true
            }
        }
    }
    var font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular) {
        didSet { needsDisplay = true }
    }
    var isEditMode = false
    var onDeleteSequence: ((Int) -> Void)?
    var onSetReference: ((String?) -> Void)?

    private let textInset = NSSize(width: 12, height: 12)

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        dirtyRect.fill()
        guard !rowNames.isEmpty else { return }

        let lineHeight = max(self.lineHeight, 1)
        let firstRow = max(Int(floor((dirtyRect.minY + verticalOffset - textInset.height) / lineHeight)), 0)
        let lastRow = min(Int(ceil((dirtyRect.maxY + verticalOffset - textInset.height) / lineHeight)), rowNames.count - 1)
        guard firstRow <= lastRow else { return }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraphStyle
        ]

        for row in firstRow...lastRow {
            let y = textInset.height + CGFloat(row) * lineHeight - verticalOffset
            let rect = NSRect(
                x: textInset.width,
                y: y,
                width: max(bounds.width - (textInset.width * 2), 0),
                height: lineHeight
            )
            (rowNames[row] as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attributes)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard onSetReference != nil else { return super.menu(for: event) }
        let row = rowIndex(at: convert(event.locationInWindow, from: nil))
        guard row >= 0, row < rowNames.count else { return super.menu(for: event) }

        let menu = NSMenu(title: "Reference")
        let setItem = NSMenuItem(title: "Set as Reference", action: #selector(setReferenceFromMenu(_:)), keyEquivalent: "")
        setItem.target = self
        setItem.representedObject = rowNames[row]
        menu.addItem(setItem)

        let clearItem = NSMenuItem(title: "Clear Reference", action: #selector(clearReferenceFromMenu(_:)), keyEquivalent: "")
        clearItem.target = self
        menu.addItem(clearItem)

        if isEditMode {
            menu.addItem(.separator())
            let deleteItem = NSMenuItem(title: "Delete Sequence", action: #selector(deleteSequenceFromMenu(_:)), keyEquivalent: "")
            deleteItem.target = self
            deleteItem.representedObject = row
            menu.addItem(deleteItem)
        }
        return menu
    }

    private func rowIndex(at point: NSPoint) -> Int {
        let y = point.y + verticalOffset - textInset.height
        guard y >= 0 else { return -1 }
        return Int(floor(y / max(lineHeight, 1)))
    }

    private var lineHeight: CGFloat {
        ceil(font.ascender - font.descender + font.leading)
    }

    @objc private func setReferenceFromMenu(_ sender: NSMenuItem) {
        onSetReference?(sender.representedObject as? String)
    }

    @objc private func clearReferenceFromMenu(_ sender: NSMenuItem) {
        onSetReference?(nil)
    }

    @objc private func deleteSequenceFromMenu(_ sender: NSMenuItem) {
        guard let row = sender.representedObject as? Int else { return }
        onDeleteSequence?(row)
    }
}

final class AlignmentViewportSequenceTextView: NSTextView {
    private struct ColumnEditState {
        let attributedText: NSAttributedString
        let selectedRanges: [NSValue]
        let columnSelectionRanges: [NSRange]
        let columnSelectionAnchor: Int?
        let columnSelectionWidth: Int
        let alignmentLength: Int
    }

    private struct AlignmentEdit {
        let row: Int
        let column: Int
        let length: Int
    }

    var onAddVerticalCursor: ((Int) -> Bool)?
    var columnSelectionAnchor: Int?
    var columnSelectionWidth: Int = 1
    var columnSelectionRanges: [NSRange] = []

    var alignmentLength = 0
    private var identityByColumn: [Double] = []
    private var majorityResidueByColumn: [UInt16] = []
    private var backgroundMode: AlignmentBackgroundMode = .residue
    private var identityColorThreshold = 0.5

    func applyAlignmentReplacement(_ replacement: String, to ranges: [NSRange]) {
        guard let textStorage else { return }
        guard !ranges.isEmpty, alignmentLength > 0 else { return }
        guard !replacement.contains("\n") else { return }

        let previousState = captureColumnEditState()
        var lines = sequenceLines()
        guard !lines.isEmpty else { return }
        let edits = normalizedEdits(from: ranges, rowCount: lines.count)
        guard !edits.isEmpty else { return }

        let replacementLength = (replacement as NSString).length
        var editGroups: [String: (column: Int, length: Int, rows: Set<Int>)] = [:]
        for edit in edits {
            let key = "\(edit.column):\(edit.length)"
            if editGroups[key] == nil {
                editGroups[key] = (edit.column, edit.length, [])
            }
            editGroups[key]?.rows.insert(edit.row)
        }

        var nextAlignmentLength = alignmentLength
        let groups = editGroups.values.sorted { lhs, rhs in
            if lhs.column == rhs.column { return lhs.length > rhs.length }
            return lhs.column > rhs.column
        }
        for group in groups {
            let extraColumns = max(replacementLength - group.length, 0)
            for row in lines.indices {
                if group.rows.contains(row) {
                    replaceCharacters(in: &lines[row], column: group.column, length: group.length, with: replacement)
                    if replacementLength < group.length {
                        lines[row] += String(repeating: "-", count: group.length - replacementLength)
                    }
                } else if extraColumns > 0 {
                    insertCharacters(String(repeating: "-", count: extraColumns), in: &lines[row], column: group.column + group.length)
                }
            }
            nextAlignmentLength += extraColumns
        }

        alignmentLength = nextAlignmentLength
        textStorage.setAttributedString(attributedSequenceText(from: lines))
        let newSelections = edits.map { edit in
            let location = (edit.row * (nextAlignmentLength + 1)) + min(edit.column + replacementLength, nextAlignmentLength)
            return NSRange(location: location, length: 0)
        }
        setSelectedRanges(
            newSelections.map(NSValue.init(range:)),
            affinity: .downstream,
            stillSelecting: false
        )
        columnSelectionRanges = newSelections
        registerColumnUndo(toRestore: previousState)
        didChangeText()
    }

    private func captureColumnEditState() -> ColumnEditState {
        let textSnapshot = textStorage?.copy() as? NSAttributedString ?? NSAttributedString(string: string)
        return ColumnEditState(
            attributedText: textSnapshot,
            selectedRanges: selectedRanges,
            columnSelectionRanges: columnSelectionRanges,
            columnSelectionAnchor: columnSelectionAnchor,
            columnSelectionWidth: columnSelectionWidth,
            alignmentLength: alignmentLength
        )
    }

    private func applyColumnEditState(_ state: ColumnEditState) {
        textStorage?.setAttributedString(state.attributedText)
        alignmentLength = state.alignmentLength
        setSelectedRanges(state.selectedRanges, affinity: .downstream, stillSelecting: false)
        columnSelectionRanges = state.columnSelectionRanges
        columnSelectionAnchor = state.columnSelectionAnchor
        columnSelectionWidth = state.columnSelectionWidth
        didChangeText()
    }

    private func registerColumnUndo(toRestore restoreState: ColumnEditState) {
        guard allowsUndo, let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { target in
            let redoState = target.captureColumnEditState()
            target.applyColumnEditState(restoreState)
            target.registerColumnUndo(toRestore: redoState)
        }
        undoManager.setActionName("Edit")
    }

    private func normalizedEdits(from ranges: [NSRange], rowCount: Int) -> [AlignmentEdit] {
        let lineSpan = alignmentLength + 1
        return ranges.compactMap { range in
            guard range.location >= 0 else { return nil }
            let row = range.location / lineSpan
            let column = range.location % lineSpan
            guard row >= 0, row < rowCount, column < alignmentLength else { return nil }
            let length = min(max(range.length, 0), alignmentLength - column)
            return AlignmentEdit(row: row, column: column, length: length)
        }
    }

    private func sequenceLines() -> [String] {
        var lines = string
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        if lines.last == "" {
            lines.removeLast()
        }
        return lines
    }

    private func attributedSequenceText(from lines: [String]) -> NSAttributedString {
        NSAttributedString(
            string: lines.joined(separator: "\n") + "\n",
            attributes: [
                .font: font ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor.labelColor
            ]
        )
    }

    private func replaceCharacters(in line: inout String, column: Int, length: Int, with replacement: String) {
        let start = line.index(line.startIndex, offsetBy: min(column, line.count))
        let end = line.index(start, offsetBy: min(length, line.distance(from: start, to: line.endIndex)))
        line.replaceSubrange(start..<end, with: replacement)
    }

    private func insertCharacters(_ insertion: String, in line: inout String, column: Int) {
        let index = line.index(line.startIndex, offsetBy: min(max(column, 0), line.count))
        line.insert(contentsOf: insertion, at: index)
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        guard isEditable else {
            super.insertText(insertString, replacementRange: replacementRange)
            return
        }
        let ranges = columnSelectionRanges
        guard ranges.count > 1 else {
            super.insertText(insertString, replacementRange: replacementRange)
            return
        }

        let replacement: String
        if let attributed = insertString as? NSAttributedString {
            replacement = attributed.string
        } else if let string = insertString as? String {
            replacement = string
        } else {
            replacement = "\(insertString)"
        }

        applyAlignmentReplacement(replacement, to: ranges)
    }

    @objc func selectColumnUp(_ sender: Any?) {
        _ = onAddVerticalCursor?(-1)
    }

    @objc func selectColumnDown(_ sender: Any?) {
        _ = onAddVerticalCursor?(1)
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isControlShift = flags.contains([.control, .shift]) && !flags.contains(.command) && !flags.contains(.option)
        if isControlShift {
            if event.keyCode == 126, onAddVerticalCursor?(-1) == true { return }
            if event.keyCode == 125, onAddVerticalCursor?(1) == true { return }
        }
        super.keyDown(with: event)
    }

    override func doCommand(by selector: Selector) {
        let flags = NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
        let isControlShift = flags.contains([.control, .shift]) && !flags.contains(.command) && !flags.contains(.option)
        if isControlShift {
            if selector == #selector(moveUp(_:)), onAddVerticalCursor?(-1) == true { return }
            if selector == #selector(moveDown(_:)), onAddVerticalCursor?(1) == true { return }
            if selector == #selector(moveUpAndModifySelection(_:)), onAddVerticalCursor?(-1) == true { return }
            if selector == #selector(moveDownAndModifySelection(_:)), onAddVerticalCursor?(1) == true { return }
        }
        super.doCommand(by: selector)
    }

    func updateAlignmentDisplay(
        alignmentLength: Int,
        identityByColumn: [Double],
        majorityResidueByColumn: [UInt16],
        backgroundMode: AlignmentBackgroundMode,
        identityColorThreshold: Double
    ) {
        let needsRedraw =
            self.alignmentLength != alignmentLength ||
            self.identityByColumn.count != identityByColumn.count ||
            self.majorityResidueByColumn.count != majorityResidueByColumn.count ||
            self.backgroundMode != backgroundMode ||
            abs(self.identityColorThreshold - identityColorThreshold) > 0.001
        self.alignmentLength = alignmentLength
        self.identityByColumn = identityByColumn
        self.majorityResidueByColumn = majorityResidueByColumn
        self.backgroundMode = backgroundMode
        self.identityColorThreshold = identityColorThreshold
        if needsRedraw {
            needsDisplay = true
        }
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard alignmentLength > 0 else { return }
        guard let font else { return }

        let charWidth = max(("M" as NSString).size(withAttributes: [.font: font]).width, 1)
        let lineHeight = max(ceil(font.ascender - font.descender + font.leading), 1)
        let inset = textContainerInset
        let lineSpan = alignmentLength + 1
        let text = string as NSString
        let textLength = text.length
        guard textLength > 0 else { return }

        let visibleMinY = max(rect.minY - inset.height, 0)
        let visibleMaxY = max(rect.maxY - inset.height, 0)
        let firstRow = max(Int(floor(visibleMinY / lineHeight)), 0)
        let lastRow = min(Int(ceil(visibleMaxY / lineHeight)), max(textLength / lineSpan, 0))
        let firstColumn = max(Int(floor((rect.minX - inset.width) / charWidth)), 0)
        let lastColumn = min(Int(ceil((rect.maxX - inset.width) / charWidth)), alignmentLength - 1)
        guard firstRow <= lastRow, firstColumn <= lastColumn else { return }

        for row in firstRow...lastRow {
            let rowStart = row * lineSpan
            guard rowStart < textLength else { continue }
            var runStart: Int?
            var runColor: NSColor?

            func flushRun(endColumn: Int) {
                guard let start = runStart, let color = runColor, endColumn > start else { return }
                color.setFill()
                let runRect = NSRect(
                    x: inset.width + CGFloat(start) * charWidth,
                    y: inset.height + CGFloat(row) * lineHeight,
                    width: CGFloat(endColumn - start) * charWidth,
                    height: lineHeight
                )
                runRect.fill()
            }

            for column in firstColumn...lastColumn {
                guard rowStart + column < textLength else { break }
                guard let color = backgroundColor(in: text, at: rowStart + column, column: column) else {
                    flushRun(endColumn: column)
                    runStart = nil
                    runColor = nil
                    continue
                }
                if runStart == nil {
                    runStart = column
                    runColor = color
                } else if color != runColor {
                    flushRun(endColumn: column)
                    runStart = column
                    runColor = color
                }
            }
            flushRun(endColumn: lastColumn + 1)
        }
    }

    private func backgroundColor(in text: NSString, at textIndex: Int, column: Int) -> NSColor? {
        switch backgroundMode {
        case .residue:
            return ResiduePalette.backgroundColor(for: text.character(at: textIndex))
        case .different:
            let residue = normalizedResidueCode(text.character(at: textIndex))
            guard let majorityResidue = majorityResidueByColumn[safe: column], majorityResidue != 0 else { return nil }
            guard residue != majorityResidue else { return nil }
            return ResiduePalette.backgroundColor(for: residue)
        case .identity:
            return identityByColumn[safe: column].flatMap {
                IdentityPalette.backgroundColor(for: $0, threshold: identityColorThreshold)
            }
        }
    }
}

final class AlignmentViewportRulerView: NSRulerView {
    static let rulerHeight: CGFloat = 20

    private var alignmentLength = 0
    private var baseFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    private var textInset: CGFloat = 12
    private let step = 10

    init(scrollView: NSScrollView) {
        super.init(scrollView: scrollView, orientation: .horizontalRuler)
        clientView = scrollView.documentView
        ruleThickness = Self.rulerHeight
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func update(length: Int, font: NSFont, textInset: CGFloat) {
        alignmentLength = max(length, 0)
        baseFont = font
        self.textInset = textInset
        needsDisplay = true
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        rect.fill()
        guard alignmentLength > 0, let scrollView else { return }

        let glyphWidth = max(("M" as NSString).size(withAttributes: [.font: baseFont]).width, 1)
        let labelFont = NSFont.monospacedSystemFont(ofSize: max(baseFont.pointSize - 4, 7), weight: .regular)
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let visibleRect = scrollView.contentView.bounds
        let visibleStart = max(Int(floor((visibleRect.minX - textInset) / glyphWidth)) + 1, 1)
        let visibleEnd = min(Int(ceil((visibleRect.maxX - textInset) / glyphWidth)) + 1, alignmentLength)
        guard visibleStart <= visibleEnd else { return }

        var tick = ((visibleStart + step - 1) / step) * step
        while tick <= visibleEnd {
            let documentX = textInset + (CGFloat(tick - 1) * glyphWidth) + glyphWidth
            let x = documentX - visibleRect.minX
            let markerPath = NSBezierPath()
            markerPath.move(to: NSPoint(x: x, y: 14))
            markerPath.line(to: NSPoint(x: x, y: 19))
            NSColor.tertiaryLabelColor.setStroke()
            markerPath.lineWidth = 1
            markerPath.stroke()

            let label = "\(tick)" as NSString
            let labelSize = label.size(withAttributes: labelAttributes)
            label.draw(at: NSPoint(x: x - labelSize.width / 2, y: 2), withAttributes: labelAttributes)
            tick += step
        }
    }
}
