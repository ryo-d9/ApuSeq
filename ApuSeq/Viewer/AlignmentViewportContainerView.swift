import AppKit

final class AlignmentViewportContainerView: NSView, NSSplitViewDelegate {
    private static let minimumNameWidth: CGFloat = 90
    private static let minimumSequenceWidth: CGFloat = 160
    private static let splitViewAutosaveName = NSSplitView.AutosaveName("ApuSeqAlignmentViewportSplitView")

    let nameColumnView: AlignmentViewportNameColumnView
    let sequenceScrollView: NSScrollView
    let auxiliaryNameScrollView: NSScrollView
    let auxiliarySequenceScrollView: NSScrollView
    let sequenceTextView: AlignmentViewportSequenceTextView
    let auxiliaryNameTextView: NSTextView
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
        auxiliaryNameTextView: NSTextView,
        auxiliarySequenceTextView: NSTextView
    ) {
        self.nameColumnView = nameColumnView
        self.sequenceTextView = sequenceTextView
        self.auxiliaryNameTextView = auxiliaryNameTextView
        self.auxiliarySequenceTextView = auxiliarySequenceTextView

        sequenceScrollView = NSScrollView()
        sequenceScrollView.documentView = sequenceTextView
        sequenceScrollView.hasVerticalScroller = true
        sequenceScrollView.hasHorizontalScroller = true
        sequenceScrollView.autohidesScrollers = true
        sequenceScrollView.borderType = .noBorder

        auxiliaryNameScrollView = NSScrollView()
        auxiliaryNameScrollView.documentView = auxiliaryNameTextView
        auxiliaryNameScrollView.hasVerticalScroller = false
        auxiliaryNameScrollView.hasHorizontalScroller = false
        auxiliaryNameScrollView.autohidesScrollers = true
        auxiliaryNameScrollView.borderType = .noBorder

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
        onAddSequence: @escaping () -> Void,
        onRenameSequence: @escaping (Int) -> Void,
        onDeleteSequence: @escaping (Int) -> Void,
        onSetReference: @escaping (String?) -> Void
    ) {
        if nameColumnView.rowNames != names {
            nameColumnView.rowNames = names
        }
        nameColumnView.isEditMode = isEditMode
        nameColumnView.onAddSequence = onAddSequence
        nameColumnView.onRenameSequence = onRenameSequence
        nameColumnView.onDeleteSequence = onDeleteSequence
        nameColumnView.onSetReference = onSetReference
        sequenceTextView.onAddSequence = onAddSequence
    }

    func updateAuxiliaryPanel(
        nameText: NSAttributedString,
        sequenceText: NSAttributedString,
        lineCount: Int,
        fontSize: Double
    ) {
        auxiliaryNameTextView.textStorage?.setAttributedString(nameText)
        auxiliarySequenceTextView.textStorage?.setAttributedString(sequenceText)

        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let lineHeight = max(ceil(font.ascender - font.descender + font.leading), 1)
        let height = lineCount > 0 ? max(CGFloat(lineCount) * lineHeight + 8, 24) : 0
        let isVisible = lineCount > 0
        leftAuxHeightConstraint?.constant = height
        rightAuxHeightConstraint?.constant = height
        auxiliaryNameScrollView.isHidden = !isVisible
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

        var nameOrigin = auxiliaryNameScrollView.contentView.bounds.origin
        if abs(nameOrigin.x) > 0.5 {
            nameOrigin.x = 0
            auxiliaryNameScrollView.contentView.scroll(to: nameOrigin)
            auxiliaryNameScrollView.reflectScrolledClipView(auxiliaryNameScrollView.contentView)
        }
    }

    private func setupLayout() {
        [
            splitView, leftPane, rightPane, leftStack, rightStack, leftHeaderSpacer,
            nameColumnView, sequenceScrollView, auxiliaryNameScrollView, auxiliarySequenceScrollView, rulerView
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
        leftStack.addArrangedSubview(auxiliaryNameScrollView)

        rightStack.orientation = .vertical
        rightStack.spacing = 0
        rightStack.addArrangedSubview(rulerView)
        rightStack.addArrangedSubview(sequenceScrollView)
        rightStack.addArrangedSubview(auxiliarySequenceScrollView)

        leftAuxHeightConstraint = auxiliaryNameScrollView.heightAnchor.constraint(equalToConstant: 0)
        rightAuxHeightConstraint = auxiliarySequenceScrollView.heightAnchor.constraint(equalToConstant: 0)
        leftAuxHeightConstraint?.isActive = true
        rightAuxHeightConstraint?.isActive = true
        auxiliaryNameScrollView.isHidden = true
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
