import AppKit

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
