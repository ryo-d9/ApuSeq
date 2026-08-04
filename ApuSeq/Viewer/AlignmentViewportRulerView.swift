import AppKit

final class AlignmentViewportRulerView: NSRulerView {
    static let minimumRulerHeight: CGFloat = 20
    private static let labelTopPadding: CGFloat = 2
    private static let labelTickSpacing: CGFloat = 0.5
    private static let tickLength: CGFloat = 6
    private static let bottomPadding: CGFloat = 2

    private var alignmentLength = 0
    private var baseFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    private var textInset: CGFloat = 12
    private let step = 10

    init(scrollView: NSScrollView) {
        super.init(scrollView: scrollView, orientation: .horizontalRuler)
        clientView = scrollView.documentView
        ruleThickness = Self.rulerHeight(for: baseFont)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func update(length: Int, font: NSFont, textInset: CGFloat) {
        alignmentLength = max(length, 0)
        baseFont = font
        self.textInset = textInset
        ruleThickness = Self.rulerHeight(for: font)
        needsDisplay = true
    }

    static func rulerHeight(for font: NSFont) -> CGFloat {
        let labelFont = Self.labelFont(for: font)
        return max(
            Self.minimumRulerHeight,
            ceil(
                Self.labelTopPadding
                + alignmentLineHeight(for: labelFont)
                + Self.labelTickSpacing
                + Self.tickLength
                + Self.bottomPadding
            )
        )
    }

    private static func labelFont(for font: NSFont) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: max(font.pointSize - 4, 7), weight: .regular)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        rect.fill()
        guard alignmentLength > 0, let scrollView else { return }

        let glyphWidth = max(("M" as NSString).size(withAttributes: [.font: baseFont]).width, 1)
        let labelFont = Self.labelFont(for: baseFont)
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
            let label = "\(tick)" as NSString
            let labelSize = label.size(withAttributes: labelAttributes)
            let labelY = Self.labelTopPadding
            let tickTop = ceil(labelY + labelSize.height + Self.labelTickSpacing)
            let tickBottom = max(tickTop, min(tickTop + Self.tickLength, bounds.height - Self.bottomPadding))
            let markerPath = NSBezierPath()
            markerPath.move(to: NSPoint(x: x, y: tickTop))
            markerPath.line(to: NSPoint(x: x, y: tickBottom))
            NSColor.tertiaryLabelColor.setStroke()
            markerPath.lineWidth = 1
            markerPath.stroke()

            label.draw(at: NSPoint(x: x - labelSize.width / 2, y: labelY), withAttributes: labelAttributes)
            tick += step
        }
    }
}
