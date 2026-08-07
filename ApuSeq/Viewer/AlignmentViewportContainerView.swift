import AppKit

final class AlignmentViewportContainerView: NSView, NSSplitViewDelegate, NSSearchFieldDelegate {
    private static let minimumNameWidth: CGFloat = 90
    private static let minimumSequenceWidth: CGFloat = 160
    private static let nameSearchHeaderHeight: CGFloat = 64
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
    private let nameFindBarView = SequenceNameFindBarView()
    private var leftHeaderHeightConstraint: NSLayoutConstraint?
    private var rulerHeightConstraint: NSLayoutConstraint?
    private var leftAuxHeightConstraint: NSLayoutConstraint?
    private var rightAuxHeightConstraint: NSLayoutConstraint?
    private var desiredNameWidth: CGFloat = 180
    private var hasAppliedInitialNameWidth = false
    private var pendingInitialNameWidth: CGFloat?
    private var lastSequenceHorizontalOffset = CGFloat.greatestFiniteMagnitude
    private var lastNameFindFocusRequestID = -1
    private var isNameFindBarPresented = false
    var onNameFindTextChanged: ((String) -> Void)?
    var onNameFindSubmit: ((Int) -> Void)?
    var onNameFindClose: (() -> Void)?

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
        nameColumnView.onScrollWheel = { [weak self] event in
            self?.scrollSequenceVerticallyFromNameColumn(with: event)
        }
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
        sequences: [String],
        isEditMode: Bool,
        canEditSequenceNames: Bool,
        onAddSequence: @escaping () -> Void,
        onAddFASTAFromClipboard: @escaping () -> Void,
        onRenameSequence: @escaping (Int) -> Void,
        onDeleteSequence: @escaping (Int) -> Void,
        onSetReference: @escaping (String?) -> Void
    ) {
        if nameColumnView.rowNames != names {
            nameColumnView.rowNames = names
        }
        nameColumnView.rowSequences = sequences
        sequenceTextView.rowNames = names
        nameColumnView.isEditMode = isEditMode
        nameColumnView.canEditSequenceNames = canEditSequenceNames
        nameColumnView.onAddSequence = onAddSequence
        nameColumnView.onAddFASTAFromClipboard = onAddFASTAFromClipboard
        nameColumnView.onRenameSequence = onRenameSequence
        nameColumnView.onDeleteSequence = onDeleteSequence
        nameColumnView.onSetReference = onSetReference
        sequenceTextView.onAddSequence = onAddSequence
        sequenceTextView.canAddSequenceFromMenu = canEditSequenceNames
    }

    func updateHighlightedNameRow(_ row: Int?) {
        nameColumnView.highlightedRowIndex = row
    }

    func updateNameFindBar(
        isPresented: Bool,
        text: String,
        statusText: String?,
        focusRequestID: Int
    ) {
        isNameFindBarPresented = isPresented
        nameFindBarView.isHidden = !isPresented
        nameFindBarView.update(text: text, statusText: statusText)
        updateHeaderHeights()
        guard isPresented, focusRequestID != lastNameFindFocusRequestID else { return }
        lastNameFindFocusRequestID = focusRequestID
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.nameFindBarView.focusSearchField()
        }
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
        let lineHeight = alignmentLineHeight(for: font)
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

    func updateRuler(length: Int, font: NSFont, textInset: CGFloat) {
        let rulerHeight = AlignmentViewportRulerView.rulerHeight(for: font)
        if abs((rulerHeightConstraint?.constant ?? 0) - rulerHeight) > 0.5 {
            rulerHeightConstraint?.constant = rulerHeight
        }
        updateHeaderHeights()
        rulerView.update(length: length, font: font, textInset: textInset)
    }

    func updateNameColumnWidth(_ width: CGFloat) {
        guard !hasAppliedInitialNameWidth else { return }
        pendingInitialNameWidth = max(width, Self.minimumNameWidth)
        applyInitialSplitPositionIfNeeded()
    }

    override func layout() {
        super.layout()
        applyInitialSplitPositionIfNeeded()
        updateNameColumnVerticalOffset()
        syncAuxiliaryHorizontalOffset()
    }

    func updateNameColumnVerticalOffset() {
        nameColumnView.verticalOffset = sequenceScrollView.contentView.bounds.origin.y
    }

    func scrollNameRowToVisible(_ row: Int) {
        guard row >= 0, row < nameColumnView.rowNames.count else { return }
        let lineHeight = alignmentLineHeight(for: nameColumnView.font)
        let targetY = max(CGFloat(row) * lineHeight + sequenceTextView.textContainerInset.height - (sequenceScrollView.contentView.bounds.height / 2), 0)
        var origin = sequenceScrollView.contentView.bounds.origin
        origin.y = min(targetY, maxVerticalSequenceOffset)
        sequenceScrollView.contentView.scroll(to: origin)
        sequenceScrollView.reflectScrolledClipView(sequenceScrollView.contentView)
        handleSequenceBoundsChange()
    }

    func handleSequenceBoundsChange() {
        let origin = sequenceScrollView.contentView.bounds.origin
        updateNameColumnVerticalOffset()
        guard abs(origin.x - lastSequenceHorizontalOffset) > 0.5 else { return }
        lastSequenceHorizontalOffset = origin.x
        syncAuxiliaryHorizontalOffset()
        rulerView.needsDisplay = true
    }

    private func scrollSequenceVerticallyFromNameColumn(with event: NSEvent) {
        let horizontalOffset = sequenceScrollView.contentView.bounds.origin.x
        sequenceScrollView.scrollWheel(with: event)
        var origin = sequenceScrollView.contentView.bounds.origin
        if abs(origin.x - horizontalOffset) > 0.5 {
            origin.x = horizontalOffset
            sequenceScrollView.contentView.scroll(to: origin)
            sequenceScrollView.reflectScrolledClipView(sequenceScrollView.contentView)
        }
        handleSequenceBoundsChange()
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
            nameColumnView, sequenceScrollView, auxiliaryNameScrollView, auxiliarySequenceScrollView, rulerView,
            nameFindBarView
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

        nameFindBarView.isHidden = true
        nameFindBarView.onTextChanged = { [weak self] text in
            self?.onNameFindTextChanged?(text)
        }
        nameFindBarView.onSubmit = { [weak self] direction in
            self?.onNameFindSubmit?(direction)
        }
        nameFindBarView.onClose = { [weak self] in
            self?.onNameFindClose?()
        }
        leftHeaderSpacer.addSubview(nameFindBarView)

        leftAuxHeightConstraint = auxiliaryNameScrollView.heightAnchor.constraint(equalToConstant: 0)
        rightAuxHeightConstraint = auxiliarySequenceScrollView.heightAnchor.constraint(equalToConstant: 0)
        leftAuxHeightConstraint?.isActive = true
        rightAuxHeightConstraint?.isActive = true
        auxiliaryNameScrollView.isHidden = true
        auxiliarySequenceScrollView.isHidden = true

        let leftHeaderHeightConstraint = leftHeaderSpacer.heightAnchor.constraint(equalToConstant: AlignmentViewportRulerView.minimumRulerHeight)
        let rulerHeightConstraint = rulerView.heightAnchor.constraint(equalToConstant: AlignmentViewportRulerView.minimumRulerHeight)
        self.leftHeaderHeightConstraint = leftHeaderHeightConstraint
        self.rulerHeightConstraint = rulerHeightConstraint

        NSLayoutConstraint.activate([
            splitView.leadingAnchor.constraint(equalTo: leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: trailingAnchor),
            splitView.topAnchor.constraint(equalTo: topAnchor),
            splitView.bottomAnchor.constraint(equalTo: bottomAnchor),

            leftStack.leadingAnchor.constraint(equalTo: leftPane.leadingAnchor),
            leftStack.trailingAnchor.constraint(equalTo: leftPane.trailingAnchor),
            leftStack.topAnchor.constraint(equalTo: leftPane.topAnchor),
            leftStack.bottomAnchor.constraint(equalTo: leftPane.bottomAnchor),

            nameFindBarView.leadingAnchor.constraint(equalTo: leftHeaderSpacer.leadingAnchor, constant: 6),
            nameFindBarView.trailingAnchor.constraint(equalTo: leftHeaderSpacer.trailingAnchor, constant: -6),
            nameFindBarView.topAnchor.constraint(equalTo: leftHeaderSpacer.topAnchor, constant: 4),
            nameFindBarView.bottomAnchor.constraint(equalTo: leftHeaderSpacer.bottomAnchor, constant: -4),

            rightStack.leadingAnchor.constraint(equalTo: rightPane.leadingAnchor),
            rightStack.trailingAnchor.constraint(equalTo: rightPane.trailingAnchor),
            rightStack.topAnchor.constraint(equalTo: rightPane.topAnchor),
            rightStack.bottomAnchor.constraint(equalTo: rightPane.bottomAnchor),

            leftHeaderHeightConstraint,
            rulerHeightConstraint
        ])
    }

    private func applyInitialSplitPositionIfNeeded() {
        guard !hasAppliedInitialNameWidth else { return }
        guard let pendingInitialNameWidth else { return }
        guard splitView.subviews.count >= 2 else { return }
        guard bounds.width >= Self.minimumNameWidth + splitView.dividerThickness + Self.minimumSequenceWidth else { return }

        if let autosavedNameWidth, autosavedNameWidth > Self.minimumNameWidth + 0.5 {
            desiredNameWidth = autosavedNameWidth
            hasAppliedInitialNameWidth = true
            return
        }

        let maxAllowed = max(Self.minimumNameWidth, bounds.width - splitView.dividerThickness - Self.minimumSequenceWidth)
        let clamped = min(max(pendingInitialNameWidth, Self.minimumNameWidth), maxAllowed)
        if abs(splitView.subviews[0].frame.width - clamped) > 0.5 {
            splitView.setPosition(clamped, ofDividerAt: 0)
        }
        desiredNameWidth = clamped
        hasAppliedInitialNameWidth = true
    }

    private func updateHeaderHeights() {
        let rulerHeight = rulerHeightConstraint?.constant ?? AlignmentViewportRulerView.minimumRulerHeight
        let targetLeftHeaderHeight = isNameFindBarPresented
            ? max(rulerHeight, Self.nameSearchHeaderHeight)
            : rulerHeight
        if abs((leftHeaderHeightConstraint?.constant ?? 0) - targetLeftHeaderHeight) > 0.5 {
            leftHeaderHeightConstraint?.constant = targetLeftHeaderHeight
            needsLayout = true
        }
    }

    private var autosavedNameWidth: CGFloat? {
        let key = "NSSplitView Subview Frames \(Self.splitViewAutosaveName)"
        guard let frames = UserDefaults.standard.array(forKey: key) as? [String],
              let firstFrame = frames.first else {
            return nil
        }
        let values = firstFrame
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
        guard values.count >= 3 else { return nil }
        guard let width = Double(values[2]) else { return nil }
        return CGFloat(width)
    }

    private var maxVerticalSequenceOffset: CGFloat {
        guard let documentView = sequenceScrollView.documentView else { return 0 }
        return max(documentView.bounds.height - sequenceScrollView.contentView.bounds.height, 0)
    }

    func splitView(_ splitView: NSSplitView, constrainSplitPosition proposedPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        let maxAllowed = max(Self.minimumNameWidth, bounds.width - splitView.dividerThickness - Self.minimumSequenceWidth)
        return min(max(proposedPosition, Self.minimumNameWidth), maxAllowed)
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard splitView.subviews.count >= 2 else { return }
        guard bounds.width >= Self.minimumNameWidth + splitView.dividerThickness + Self.minimumSequenceWidth else { return }
        guard hasAppliedInitialNameWidth else { return }
        desiredNameWidth = splitView.subviews[0].frame.width
        rulerView.needsDisplay = true
    }

    func splitView(_ splitView: NSSplitView, shouldAdjustSizeOfSubview view: NSView) -> Bool {
        view !== leftPane
    }

}

private final class SequenceNameFindBarView: NSView, NSSearchFieldDelegate {
    private let stackView = NSStackView()
    private let footerStackView = NSStackView()
    private let searchField = SequenceNameSearchField()
    private let statusLabel = NSTextField(labelWithString: "")
    private let footerSpacer = NSView()
    private let doneButton = NSButton()

    var onTextChanged: ((String) -> Void)?
    var onSubmit: ((Int) -> Void)?
    var onClose: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func update(text: String, statusText: String?) {
        if searchField.stringValue != text {
            searchField.stringValue = text
        }
        statusLabel.stringValue = statusText ?? ""
        statusLabel.isHidden = statusText == nil
    }

    func focusSearchField() {
        window?.makeFirstResponder(searchField)
        searchField.selectText(nil)
    }

    func controlTextDidChange(_ notification: Notification) {
        guard notification.object as? NSSearchField === searchField else { return }
        onTextChanged?(searchField.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard control === searchField else { return false }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            let flags = NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
            onSubmit?(flags.contains(.shift) ? -1 : 1)
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            onClose?()
            return true
        }
        return false
    }

    private func setupLayout() {
        [
            stackView, footerStackView, searchField, statusLabel, footerSpacer, doneButton
        ].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }

        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.distribution = .fill
        stackView.spacing = 5
        addSubview(stackView)

        footerStackView.orientation = .horizontal
        footerStackView.alignment = .centerY
        footerStackView.distribution = .fill
        footerStackView.spacing = 6
        stackView.addArrangedSubview(searchField)
        stackView.addArrangedSubview(footerStackView)
        footerStackView.addArrangedSubview(statusLabel)
        footerStackView.addArrangedSubview(footerSpacer)
        footerStackView.addArrangedSubview(doneButton)

        searchField.placeholderString = String(localized: "Sequence name")
        searchField.controlSize = .small
        searchField.delegate = self
        searchField.sendsSearchStringImmediately = false
        searchField.sendsWholeSearchString = true
        searchField.onCancel = { [weak self] in
            self?.onClose?()
        }
        searchField.onTextChanged = { [weak self] text in
            self?.onTextChanged?(text)
        }
        searchField.setAccessibilityIdentifier("sequence-name-search-field")

        statusLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        footerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        footerSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        doneButton.title = String(localized: "Done")
        doneButton.bezelStyle = .rounded
        doneButton.controlSize = .small
        doneButton.target = self
        doneButton.action = #selector(close(_:))
        doneButton.setAccessibilityLabel(String(localized: "Done"))

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor),

            searchField.leadingAnchor.constraint(equalTo: stackView.leadingAnchor),
            searchField.trailingAnchor.constraint(equalTo: stackView.trailingAnchor),
            searchField.heightAnchor.constraint(equalToConstant: 22),
            searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 40),

            footerStackView.leadingAnchor.constraint(equalTo: stackView.leadingAnchor),
            footerStackView.trailingAnchor.constraint(equalTo: stackView.trailingAnchor),
            footerStackView.heightAnchor.constraint(equalToConstant: 22),

            doneButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 48),
            doneButton.heightAnchor.constraint(equalToConstant: 22)
        ])
    }

    @objc private func close(_ sender: Any?) {
        onClose?()
    }
}

private final class SequenceNameSearchField: NSSearchField {
    var onCancel: (() -> Void)?
    var onTextChanged: ((String) -> Void)?

    override func cancelOperation(_ sender: Any?) {
        if stringValue.isEmpty {
            onCancel?()
        } else {
            stringValue = ""
            onTextChanged?(stringValue)
        }
    }
}
