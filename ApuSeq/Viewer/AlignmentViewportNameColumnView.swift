import AppKit

final class AlignmentViewportNameColumnView: NSView {
    var rowNames: [String] = [] {
        didSet { needsDisplay = true }
    }
    var rowSequences: [String] = []
    var highlightedRowIndex: Int? {
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
    var canEditSequenceNames = true
    var onAddSequence: (() -> Void)?
    var onAddFASTAFromClipboard: (() -> Void)?
    var onRenameSequence: ((Int) -> Void)?
    var onDeleteSequence: ((Int) -> Void)?
    var onSetReference: ((String?) -> Void)?
    var onScrollWheel: ((NSEvent) -> Void)?

    private let textInset = NSSize(width: 12, height: 12)

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        clipsToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        dirtyRect.fill()
        guard !rowNames.isEmpty else { return }
        guard let visibleRows = visibleRowRange(in: dirtyRect) else { return }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraphStyle
        ]

        for row in visibleRows {
            let y = rowOriginY(row)
            let rect = NSRect(
                x: textInset.width,
                y: y,
                width: max(bounds.width - (textInset.width * 2), 0),
                height: lineHeight
            )
            if row == highlightedRowIndex {
                NSColor.selectedContentBackgroundColor.withAlphaComponent(0.16).setFill()
                NSRect(x: 0, y: y, width: bounds.width, height: lineHeight).fill()
            }
            (rowNames[row] as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attributes)
        }
    }

    override func isAccessibilityElement() -> Bool {
        true
    }

    override func accessibilityRole() -> NSAccessibility.Role? {
        .group
    }

    override func accessibilityLabel() -> String? {
        AppStrings.sequenceNames
    }

    override func accessibilityChildren() -> [Any]? {
        guard let visibleRows = visibleRowRange(in: bounds) else { return [] }
        return visibleRows.map { row in
            let element = NSAccessibilityElement()
            element.setAccessibilityParent(self)
            element.setAccessibilityRole(.staticText)
            element.setAccessibilityLabel(AppStrings.accessibilitySequenceName(rowIndex: row + 1, name: rowNames[row]))
            element.setAccessibilityFrameInParentSpace(rowRect(row))
            return element
        }
    }

    override func scrollWheel(with event: NSEvent) {
        guard abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX) else {
            super.scrollWheel(with: event)
            return
        }
        onScrollWheel?(event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let row = rowIndex(at: convert(event.locationInWindow, from: nil))
        guard row >= 0, row < rowNames.count else {
            guard isEditMode && canEditSequenceNames else { return super.menu(for: event) }
            let menu = NSMenu(title: AppStrings.sequenceMenu)
            let addItem = NSMenuItem(title: AppStrings.addSequence, action: #selector(addSequenceFromMenu(_:)), keyEquivalent: "")
            addItem.target = self
            menu.addItem(addItem)
            let addFASTAItem = NSMenuItem(title: AppStrings.addFASTAFromClipboard, action: #selector(addFASTAFromClipboardFromMenu(_:)), keyEquivalent: "")
            addFASTAItem.target = self
            menu.addItem(addFASTAItem)
            return menu
        }

        let menu = NSMenu(title: AppStrings.referenceMenu)
        let copyItem = NSMenuItem(title: AppStrings.copySequence, action: #selector(copySequenceFromMenu(_:)), keyEquivalent: "")
        copyItem.target = self
        copyItem.representedObject = row
        menu.addItem(copyItem)
        let copyFASTAItem = NSMenuItem(title: AppStrings.copyAsFASTA, action: #selector(copyFASTAFromMenu(_:)), keyEquivalent: "")
        copyFASTAItem.target = self
        copyFASTAItem.representedObject = row
        menu.addItem(copyFASTAItem)
        menu.addItem(.separator())

        let setItem = NSMenuItem(title: AppStrings.setAsReference, action: #selector(setReferenceFromMenu(_:)), keyEquivalent: "")
        setItem.target = self
        setItem.representedObject = rowNames[row]
        menu.addItem(setItem)

        let clearItem = NSMenuItem(title: AppStrings.clearReference, action: #selector(clearReferenceFromMenu(_:)), keyEquivalent: "")
        clearItem.target = self
        menu.addItem(clearItem)

        if isEditMode && canEditSequenceNames {
            menu.addItem(.separator())
            let addItem = NSMenuItem(title: AppStrings.addSequence, action: #selector(addSequenceFromMenu(_:)), keyEquivalent: "")
            addItem.target = self
            menu.addItem(addItem)

            let addFASTAItem = NSMenuItem(title: AppStrings.addFASTAFromClipboard, action: #selector(addFASTAFromClipboardFromMenu(_:)), keyEquivalent: "")
            addFASTAItem.target = self
            menu.addItem(addFASTAItem)

            let renameItem = NSMenuItem(title: AppStrings.renameSequence, action: #selector(renameSequenceFromMenu(_:)), keyEquivalent: "")
            renameItem.target = self
            renameItem.representedObject = row
            menu.addItem(renameItem)

            if rowNames.count > 1 {
                let deleteItem = NSMenuItem(title: AppStrings.deleteSequence, action: #selector(deleteSequenceFromMenu(_:)), keyEquivalent: "")
                deleteItem.target = self
                deleteItem.representedObject = row
                menu.addItem(deleteItem)
            }
        }
        return menu
    }

    private func rowIndex(at point: NSPoint) -> Int {
        let y = point.y + verticalOffset - textInset.height
        guard y >= 0 else { return -1 }
        return Int(floor(y / max(lineHeight, 1)))
    }

    private func visibleRowRange(in rect: NSRect) -> ClosedRange<Int>? {
        guard !rowNames.isEmpty else { return nil }
        let lineHeight = max(self.lineHeight, 1)
        let firstRow = max(Int(floor((rect.minY + verticalOffset - textInset.height) / lineHeight)), 0)
        let lastRow = min(Int(ceil((rect.maxY + verticalOffset - textInset.height) / lineHeight)), rowNames.count - 1)
        guard firstRow <= lastRow else { return nil }
        return firstRow...lastRow
    }

    private func rowRect(_ row: Int) -> NSRect {
        NSRect(x: 0, y: rowOriginY(row), width: bounds.width, height: lineHeight)
    }

    private func rowOriginY(_ row: Int) -> CGFloat {
        textInset.height + CGFloat(row) * lineHeight - verticalOffset
    }

    private var lineHeight: CGFloat {
        alignmentLineHeight(for: font)
    }

    @objc private func setReferenceFromMenu(_ sender: NSMenuItem) {
        onSetReference?(sender.representedObject as? String)
    }

    @objc private func clearReferenceFromMenu(_ sender: NSMenuItem) {
        onSetReference?(nil)
    }

    @objc private func copySequenceFromMenu(_ sender: NSMenuItem) {
        guard let row = sender.representedObject as? Int else { return }
        guard row >= 0, row < rowSequences.count else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(rowSequences[row], forType: .string)
    }

    @objc private func copyFASTAFromMenu(_ sender: NSMenuItem) {
        guard let row = sender.representedObject as? Int else { return }
        guard row >= 0, row < rowNames.count, row < rowSequences.count else { return }
        let fasta = AlignmentSerializer.serialize(
            rows: [AlignmentRow(name: rowNames[row], sequence: rowSequences[row])],
            preferredFormat: .fasta
        )
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(fasta, forType: .string)
    }

    @objc private func addSequenceFromMenu(_ sender: NSMenuItem) {
        onAddSequence?()
    }

    @objc private func addFASTAFromClipboardFromMenu(_ sender: NSMenuItem) {
        onAddFASTAFromClipboard?()
    }

    @objc private func renameSequenceFromMenu(_ sender: NSMenuItem) {
        guard let row = sender.representedObject as? Int else { return }
        onRenameSequence?(row)
    }

    @objc private func deleteSequenceFromMenu(_ sender: NSMenuItem) {
        guard let row = sender.representedObject as? Int else { return }
        onDeleteSequence?(row)
    }
}
