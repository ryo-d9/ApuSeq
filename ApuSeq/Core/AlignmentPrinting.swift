import AppKit
import Foundation

struct AlignmentPrintOptions: Equatable {
    var maximumColumnsPerBlock = 100
    var referenceName: String?
    var referenceSequence: String?
    var includesConsensus = true
    var includesIdentity = true
    var usesResidueBackground = true
    var fontSize: CGFloat = 9

    nonisolated static let `default` = AlignmentPrintOptions()
}

struct AlignmentPrintPage: Equatable {
    let columnRange: Range<Int>
    let rowRange: Range<Int>
}

enum AlignmentPrinter {
    @MainActor
    static func runPrintPanel(
        alignment: AlignmentData,
        title: String,
        options: AlignmentPrintOptions = .default,
        window: NSWindow?
    ) {
        let printInfo = configuredPrintInfo()
        let printView = AlignmentPrintView(alignment: alignment, title: title, options: options, printInfo: printInfo)
        let operation = NSPrintOperation(view: printView, printInfo: printInfo)
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        operation.printPanel.options = [
            .showsCopies,
            .showsPageRange,
            .showsPaperSize,
            .showsOrientation,
            .showsScaling,
            .showsPageSetupAccessory,
            .showsPreview
        ]

        if let window {
            operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            operation.run()
        }
    }

    static func configuredPrintInfo() -> NSPrintInfo {
        let printInfo = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo.shared
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = false
        printInfo.isVerticallyCentered = false
        return printInfo
    }
}

enum AlignmentPrintLayout {
    static func pages(
        alignment: AlignmentData,
        options: AlignmentPrintOptions,
        pageContentSize: CGSize,
        nameColumnWidth: CGFloat,
        characterWidth: CGFloat,
        lineHeight: CGFloat
    ) -> [AlignmentPrintPage] {
        guard !alignment.rows.isEmpty, alignment.length > 0 else { return [] }

        let columnsPerBlock = resolvedColumnsPerBlock(
            maximumColumnsPerBlock: options.maximumColumnsPerBlock,
            pageContentWidth: pageContentSize.width,
            nameColumnWidth: nameColumnWidth,
            characterWidth: characterWidth
        )
        let auxiliaryLineCount =
            (options.referenceSequence == nil ? 0 : 1) +
            (options.includesConsensus ? 1 : 0) +
            (options.includesIdentity ? 1 : 0)
        let rowCapacity = rowsPerPage(
            pageContentHeight: pageContentSize.height,
            lineHeight: lineHeight,
            auxiliaryLineCount: auxiliaryLineCount
        )

        var pages: [AlignmentPrintPage] = []
        var columnStart = 0
        while columnStart < alignment.length {
            let columnEnd = min(columnStart + columnsPerBlock, alignment.length)
            var rowStart = 0
            while rowStart < alignment.rows.count {
                let rowEnd = min(rowStart + rowCapacity, alignment.rows.count)
                pages.append(
                    AlignmentPrintPage(
                        columnRange: columnStart..<columnEnd,
                        rowRange: rowStart..<rowEnd
                    )
                )
                rowStart = rowEnd
            }
            columnStart = columnEnd
        }
        return pages
    }

    static func resolvedColumnsPerBlock(
        maximumColumnsPerBlock: Int,
        pageContentWidth: CGFloat,
        nameColumnWidth: CGFloat,
        characterWidth: CGFloat
    ) -> Int {
        guard characterWidth > 0 else { return max(maximumColumnsPerBlock, 1) }
        let sequenceWidth = max(pageContentWidth - nameColumnWidth - 12, characterWidth)
        let fittingColumns = max(Int(floor(sequenceWidth / characterWidth)), 1)
        return max(min(maximumColumnsPerBlock, fittingColumns), 1)
    }

    static func rowsPerPage(pageContentHeight: CGFloat, lineHeight: CGFloat, auxiliaryLineCount: Int) -> Int {
        guard lineHeight > 0 else { return 1 }
        let headerHeight: CGFloat = 44
        let blockHeaderHeight = lineHeight + 8
        let auxiliaryHeight = CGFloat(auxiliaryLineCount) * lineHeight
        let auxiliaryGap: CGFloat = auxiliaryLineCount > 0 ? 8 : 0
        let footerHeight: CGFloat = 16
        let availableHeight = pageContentHeight - headerHeight - blockHeaderHeight - auxiliaryHeight - auxiliaryGap - footerHeight
        return max(Int(floor(availableHeight / lineHeight)), 1)
    }
}

final class AlignmentPrintView: NSView {
    private struct LayoutSignature: Equatable {
        let paperSize: CGSize
        let imageableBounds: CGRect
        let leftMargin: CGFloat
        let rightMargin: CGFloat
        let topMargin: CGFloat
        let bottomMargin: CGFloat

        init(printInfo: NSPrintInfo) {
            paperSize = printInfo.paperSize
            imageableBounds = printInfo.imageablePageBounds
            leftMargin = printInfo.leftMargin
            rightMargin = printInfo.rightMargin
            topMargin = printInfo.topMargin
            bottomMargin = printInfo.bottomMargin
        }
    }

    private let alignment: AlignmentData
    private let title: String
    private let options: AlignmentPrintOptions
    private let referenceLabel: String?
    private let referenceSequence: String?
    private let consensusSequence: String
    private let identityByColumn: [Double]
    private let measuredNameColumnWidth: CGFloat
    private var pages: [AlignmentPrintPage] = []
    private var pageSize = CGSize(width: 1, height: 1)
    private let contentInset: CGFloat = 4
    private var nameColumnWidth: CGFloat = 96
    private let baseFont: NSFont
    private let labelFont: NSFont
    private let headerFont: NSFont
    private let lineHeight: CGFloat
    private let characterWidth: CGFloat
    private let baseAttributes: [NSAttributedString.Key: Any]
    private let nameAttributes: [NSAttributedString.Key: Any]
    private let headerAttributes: [NSAttributedString.Key: Any]
    private let smallAttributes: [NSAttributedString.Key: Any]
    private var layoutSignature: LayoutSignature?

    override var isFlipped: Bool { true }

    init(
        alignment: AlignmentData,
        title: String,
        options: AlignmentPrintOptions = .default,
        printInfo: NSPrintInfo
    ) {
        self.alignment = alignment
        self.title = title
        self.options = options
        referenceLabel = options.referenceSequence == nil ? nil : String(format: String(localized: "Ref: %@"), options.referenceName ?? "")
        referenceSequence = options.referenceSequence
        baseFont = NSFont.monospacedSystemFont(ofSize: options.fontSize, weight: .regular)
        labelFont = NSFont.monospacedSystemFont(ofSize: options.fontSize, weight: .regular)
        headerFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
        lineHeight = ceil(baseFont.ascender - baseFont.descender + baseFont.leading + 2)
        characterWidth = max(("M" as NSString).size(withAttributes: [.font: baseFont]).width, 1)
        consensusSequence = options.includesConsensus
            ? AlignmentStatistics.consensusSequence(rows: alignment.rows, length: alignment.length)
            : ""
        identityByColumn = options.includesIdentity
            ? AlignmentStatistics.columnIdentity(rows: alignment.rows)
            : []
        measuredNameColumnWidth = AlignmentStatistics.nameColumnWidth(rows: alignment.rows, font: labelFont)
        baseAttributes = [
            .font: baseFont,
            .foregroundColor: NSColor.labelColor
        ]
        nameAttributes = [
            .font: labelFont,
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        headerAttributes = [
            .font: headerFont,
            .foregroundColor: NSColor.labelColor
        ]
        smallAttributes = [
            .font: NSFont.systemFont(ofSize: 8),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        super.init(frame: .zero)
        updateLayout(for: printInfo)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func knowsPageRange(_ range: NSRangePointer) -> Bool {
        if let printInfo = NSPrintOperation.current?.printInfo {
            updateLayout(for: printInfo)
        }
        range.pointee = NSRange(location: 1, length: max(pages.count, 1))
        return true
    }

    override func rectForPage(_ page: Int) -> NSRect {
        NSRect(
            x: 0,
            y: CGFloat(page - 1) * pageSize.height,
            width: pageSize.width,
            height: pageSize.height
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if let printInfo = NSPrintOperation.current?.printInfo {
            updateLayout(for: printInfo)
        }
        guard !pages.isEmpty else {
            drawEmptyPage(in: rectForPage(1))
            return
        }

        for pageIndex in visiblePageRange(for: dirtyRect) {
            let pageRect = rectForPage(pageIndex + 1)
            drawPage(pageIndex: pageIndex, in: pageRect)
        }
    }

    private func updateLayout(for printInfo: NSPrintInfo) {
        let signature = LayoutSignature(printInfo: printInfo)
        guard signature != layoutSignature else { return }
        layoutSignature = signature

        pageSize = Self.printablePageSize(for: printInfo)
        let contentSize = CGSize(
            width: max(pageSize.width - (contentInset * 2), 1),
            height: max(pageSize.height - (contentInset * 2), 1)
        )
        nameColumnWidth = min(max(measuredNameColumnWidth, 96), contentSize.width * 0.34)
        pages = AlignmentPrintLayout.pages(
            alignment: alignment,
            options: options,
            pageContentSize: contentSize,
            nameColumnWidth: nameColumnWidth,
            characterWidth: characterWidth,
            lineHeight: lineHeight
        )
        frame = NSRect(
            x: 0,
            y: 0,
            width: pageSize.width,
            height: pageSize.height * CGFloat(max(pages.count, 1))
        )
    }

    static func printablePageSize(for printInfo: NSPrintInfo) -> CGSize {
        let marginContentSize = CGSize(
            width: max(printInfo.paperSize.width - printInfo.leftMargin - printInfo.rightMargin, 1),
            height: max(printInfo.paperSize.height - printInfo.topMargin - printInfo.bottomMargin, 1)
        )
        let imageableBounds = printInfo.imageablePageBounds
        guard !imageableBounds.isEmpty else { return marginContentSize }
        return CGSize(
            width: max(min(marginContentSize.width, imageableBounds.width), 1),
            height: max(min(marginContentSize.height, imageableBounds.height), 1)
        )
    }

    private func visiblePageRange(for dirtyRect: NSRect) -> Range<Int> {
        guard pageSize.height > 0, !pages.isEmpty else { return 0..<0 }
        let firstIndex = max(Int(floor(dirtyRect.minY / pageSize.height)), 0)
        let lastIndex = min(Int(floor(max(dirtyRect.maxY - CGFloat.ulpOfOne, dirtyRect.minY) / pageSize.height)), pages.count - 1)
        guard firstIndex <= lastIndex else { return 0..<0 }
        return firstIndex..<(lastIndex + 1)
    }

    private func drawEmptyPage(in pageRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        pageRect.fill()
        let message = String(localized: "There is no alignment to print.") as NSString
        message.draw(at: NSPoint(x: contentInset, y: contentInset), withAttributes: headerAttributes)
    }

    private func drawPage(pageIndex: Int, in pageRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        pageRect.fill()

        let page = pages[pageIndex]
        let contentX = pageRect.minX + contentInset
        let contentTop = pageRect.minY + contentInset
        let contentWidth = pageRect.width - (contentInset * 2)
        var y = contentTop

        let titleText = title as NSString
        titleText.draw(at: NSPoint(x: contentX, y: y), withAttributes: headerAttributes)

        let pageText = String(format: String(localized: "Page %d of %d"), pageIndex + 1, pages.count) as NSString
        let pageTextSize = pageText.size(withAttributes: smallAttributes)
        pageText.draw(
            at: NSPoint(x: contentX + contentWidth - pageTextSize.width, y: y + 2),
            withAttributes: smallAttributes
        )
        y += 22

        let rangeText = String(
            format: String(localized: "Columns %d-%d"),
            page.columnRange.lowerBound + 1,
            page.columnRange.upperBound
        ) as NSString
        rangeText.draw(at: NSPoint(x: contentX, y: y), withAttributes: smallAttributes)
        y += lineHeight + 8

        for rowIndex in page.rowRange {
            let row = alignment.rows[rowIndex]
            drawName(row.name, x: contentX, y: y)
            drawSequence(row.sequence, range: page.columnRange, x: sequenceX(contentX), y: y, appliesBackground: options.usesResidueBackground)
            y += lineHeight
        }

        if referenceSequence != nil || options.includesConsensus || options.includesIdentity {
            y += 8
        }
        if let referenceLabel, let referenceSequence {
            drawName(referenceLabel, x: contentX, y: y)
            drawSequence(referenceSequence, range: page.columnRange, x: sequenceX(contentX), y: y, appliesBackground: options.usesResidueBackground)
            y += lineHeight
        }
        if options.includesConsensus {
            drawName(String(localized: "Consensus"), x: contentX, y: y)
            drawSequence(consensusSequence, range: page.columnRange, x: sequenceX(contentX), y: y, appliesBackground: options.usesResidueBackground)
            y += lineHeight
        }
        if options.includesIdentity {
            drawName(String(localized: "Identity"), x: contentX, y: y)
            let identityLowerBound = min(page.columnRange.lowerBound, identityByColumn.count)
            let identityUpperBound = min(page.columnRange.upperBound, identityByColumn.count)
            let bars = identityLowerBound < identityUpperBound
                ? IdentityBars.barString(from: identityByColumn[identityLowerBound..<identityUpperBound])
                : ""
            (bars as NSString).draw(at: NSPoint(x: sequenceX(contentX), y: y), withAttributes: nameAttributes)
        }
    }

    private func sequenceX(_ contentX: CGFloat) -> CGFloat {
        contentX + nameColumnWidth + 12
    }

    private func drawName(_ name: String, x: CGFloat, y: CGFloat) {
        (name as NSString).draw(
            with: NSRect(x: x, y: y, width: nameColumnWidth, height: lineHeight),
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: nameAttributes
        )
    }

    private func drawSequence(_ sequence: String, range: Range<Int>, x: CGFloat, y: CGFloat, appliesBackground: Bool) {
        let nsString = sequence as NSString
        let safeLower = min(max(range.lowerBound, 0), nsString.length)
        let safeUpper = min(max(range.upperBound, safeLower), nsString.length)
        guard safeUpper > safeLower else { return }
        let safeRange = safeLower..<safeUpper

        if appliesBackground {
            drawResidueBackgrounds(sequence: nsString, range: safeRange, x: x, y: y)
        }
        let substring = nsString.substring(with: NSRange(location: safeRange.lowerBound, length: safeRange.count))
        (substring as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: baseAttributes)
    }

    private func drawResidueBackgrounds(sequence: NSString, range: Range<Int>, x: CGFloat, y: CGFloat) {
        var runStart: Int?
        var runColor: NSColor?

        func flushRun(endOffset: Int) {
            guard let start = runStart, let color = runColor, endOffset > start else { return }
            color.setFill()
            NSRect(
                x: x + CGFloat(start) * characterWidth,
                y: y,
                width: CGFloat(endOffset - start) * characterWidth,
                height: lineHeight
            ).fill()
        }

        for column in range {
            let offset = column - range.lowerBound
            let color = ResiduePalette.backgroundColor(for: sequence.character(at: column))
            guard let color else {
                flushRun(endOffset: offset)
                runStart = nil
                runColor = nil
                continue
            }
            if runStart == nil {
                runStart = offset
                runColor = color
            } else if color != runColor {
                flushRun(endOffset: offset)
                runStart = offset
                runColor = color
            }
        }
        flushRun(endOffset: range.count)
    }
}
