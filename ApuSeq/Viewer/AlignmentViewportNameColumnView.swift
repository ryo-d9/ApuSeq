import AppKit

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
    var onAddSequence: (() -> Void)?
    var onRenameSequence: ((Int) -> Void)?
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
        let row = rowIndex(at: convert(event.locationInWindow, from: nil))
        guard row >= 0, row < rowNames.count else {
            guard isEditMode else { return super.menu(for: event) }
            let menu = NSMenu(title: "Sequence")
            let addItem = NSMenuItem(title: "Add Sequence...", action: #selector(addSequenceFromMenu(_:)), keyEquivalent: "")
            addItem.target = self
            menu.addItem(addItem)
            return menu
        }

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
            let addItem = NSMenuItem(title: "Add Sequence...", action: #selector(addSequenceFromMenu(_:)), keyEquivalent: "")
            addItem.target = self
            menu.addItem(addItem)

            let renameItem = NSMenuItem(title: "Rename Sequence...", action: #selector(renameSequenceFromMenu(_:)), keyEquivalent: "")
            renameItem.target = self
            renameItem.representedObject = row
            menu.addItem(renameItem)

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

    @objc private func addSequenceFromMenu(_ sender: NSMenuItem) {
        onAddSequence?()
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
