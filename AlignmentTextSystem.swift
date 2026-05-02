import AppKit
import SwiftUI

struct AlignmentTextView: NSViewRepresentable {
    let nameAttributedText: NSAttributedString
    let sequenceAttributedText: NSAttributedString
    let namesChecksum: UInt64
    let sequenceChecksum: UInt64
    let alignmentLength: Int
    let identityByColumn: [Double]
    let showsIdentityShading: Bool
    let renderedShowsResidueColors: Bool
    let fontSize: Double
    let contentVersion: Int
    let defaultNameColumnWidth: CGFloat
    let displayedRowNames: [String]
    let auxiliaryNameAttributedText: NSAttributedString
    let auxiliarySequenceAttributedText: NSAttributedString
    let auxiliaryLineCount: Int
    let preferredUnsavedFilename: String?
    @Binding var selectedResidueCount: Int
    @Binding var selectedStartPosition: Int?
    @Binding var selectedEndPosition: Int?
    let onSetReference: (String?) -> Void

    func makeNSView(context: Context) -> AlignmentContainerView {
        let namesTextView = AlignmentNameTextView(frame: .zero)
        configureNameTextView(namesTextView, fontSize: fontSize)

        let sequenceTextStorage = NSTextStorage()
        let sequenceLayoutManager = NSLayoutManager()
        let sequenceContainer = NSTextContainer(
            containerSize: CGSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
        )
        sequenceContainer.widthTracksTextView = false
        sequenceContainer.heightTracksTextView = false
        sequenceLayoutManager.addTextContainer(sequenceContainer)
        sequenceTextStorage.addLayoutManager(sequenceLayoutManager)

        let sequenceTextView = AlignmentSequenceTextView(frame: .zero, textContainer: sequenceContainer)
        configureMainTextView(sequenceTextView, fontSize: fontSize)
        sequenceTextView.delegate = context.coordinator

        let containerView = AlignmentContainerView(
            namesTextView: namesTextView,
            sequenceTextView: sequenceTextView
        )
        containerView.onSetReference = onSetReference
        containerView.updateNameRows(displayedRowNames)
        containerView.syncAuxiliaryHorizontalOffsetToSequence()
        context.coordinator.installVerticalSyncIfNeeded(for: containerView)
        return containerView
    }

    func updateNSView(_ containerView: AlignmentContainerView, context: Context) {
        containerView.updateMode(nameColumnWidth: defaultNameColumnWidth)
        containerView.onSetReference = onSetReference
        containerView.updateAuxiliaryPanel(
            nameText: auxiliaryNameAttributedText,
            sequenceText: auxiliarySequenceAttributedText,
            lineCount: auxiliaryLineCount,
            fontSize: fontSize,
            showsResidueColors: renderedShowsResidueColors
        )
        containerView.updatePreferredUnsavedFilename(preferredUnsavedFilename)
        containerView.updateNameRows(displayedRowNames)

        let fingerprint = RenderedFingerprint(
            namesChecksum: namesChecksum,
            sequenceChecksum: sequenceChecksum,
            nameLength: nameAttributedText.length,
            sequenceLength: sequenceAttributedText.length
        )
        let needsMainTextRefresh =
            (context.coordinator.lastContentVersion != contentVersion &&
             context.coordinator.lastRenderedFingerprint != fingerprint) ||
            (context.coordinator.lastResidueColorMode != renderedShowsResidueColors)

        if needsMainTextRefresh {
            containerView.namesTextView.textStorage?.setAttributedString(nameAttributedText)
            containerView.sequenceTextView.textStorage?.setAttributedString(sequenceAttributedText)

            context.coordinator.lastContentVersion = contentVersion
            context.coordinator.lastRenderedFingerprint = fingerprint
            context.coordinator.lastResidueColorMode = renderedShowsResidueColors
            let coordinator = context.coordinator
            let sequenceTextView = containerView.sequenceTextView
            DispatchQueue.main.async {
                coordinator.updateSelectedResidueCount(in: sequenceTextView)
            }
        } else if context.coordinator.lastContentVersion != contentVersion {
            context.coordinator.lastContentVersion = contentVersion
        }

        if context.coordinator.lastFontSize != fontSize {
            containerView.namesTextView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            containerView.sequenceTextView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            context.coordinator.lastFontSize = fontSize
        }
        containerView.updateIdentityShading(
            alignmentLength: alignmentLength,
            identityByColumn: identityByColumn,
            isEnabled: showsIdentityShading
        )
        containerView.updateRuler(alignmentLength: alignmentLength, fontSize: fontSize)
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
        var lastResidueColorMode = true
        private let selectedResidueCount: Binding<Int>
        private let selectedStartPosition: Binding<Int?>
        private let selectedEndPosition: Binding<Int?>
        private var verticalSyncObserverTokens: [NSObjectProtocol] = []
        private var isSyncingScroll = false
        private var pendingSelectionUpdate: DispatchWorkItem?
        private var lastSelectionSignature: SelectionSignature?
        private var lastSequenceOrigin = CGPoint(x: -.greatestFiniteMagnitude, y: -.greatestFiniteMagnitude)
        private let scrollEpsilon: CGFloat = 0.5

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
            pendingSelectionUpdate?.cancel()
            for token in verticalSyncObserverTokens {
                NotificationCenter.default.removeObserver(token)
            }
        }

        func installVerticalSyncIfNeeded(for containerView: AlignmentContainerView) {
            guard verticalSyncObserverTokens.isEmpty else { return }

            containerView.namesScrollView.contentView.postsBoundsChangedNotifications = true
            containerView.sequenceScrollView.contentView.postsBoundsChangedNotifications = true
            containerView.auxiliaryNameScrollView.contentView.postsBoundsChangedNotifications = true
            containerView.auxiliarySequenceScrollView.contentView.postsBoundsChangedNotifications = true

            let namesToken = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: containerView.namesScrollView.contentView,
                queue: .main
            ) { [weak self, weak containerView] _ in
                guard let self, let containerView else { return }
                self.syncVerticalOffset(from: containerView.namesScrollView, to: containerView.sequenceScrollView)
            }

            let sequenceToken = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: containerView.sequenceScrollView.contentView,
                queue: .main
            ) { [weak self, weak containerView] _ in
                guard let self, let containerView else { return }
                let origin = containerView.sequenceScrollView.contentView.bounds.origin
                if abs(origin.x - self.lastSequenceOrigin.x) <= self.scrollEpsilon,
                   abs(origin.y - self.lastSequenceOrigin.y) <= self.scrollEpsilon {
                    return
                }
                self.lastSequenceOrigin = origin
                self.syncVerticalOffset(from: containerView.sequenceScrollView, to: containerView.namesScrollView)
                containerView.syncRulerHorizontalOffsetToSequence()
                containerView.syncAuxiliaryHorizontalOffsetToSequence()
            }

            let auxiliaryNameToken = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: containerView.auxiliaryNameScrollView.contentView,
                queue: .main
            ) { [weak self, weak containerView] _ in
                guard let self, let containerView else { return }
                self.syncHorizontalOffset(from: containerView.auxiliaryNameScrollView, to: containerView.namesScrollView)
            }

            let auxiliarySequenceToken = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: containerView.auxiliarySequenceScrollView.contentView,
                queue: .main
            ) { [weak self, weak containerView] _ in
                guard let self, let containerView else { return }
                self.syncHorizontalOffset(from: containerView.auxiliarySequenceScrollView, to: containerView.sequenceScrollView)
                containerView.syncRulerHorizontalOffsetToSequence()
            }

            verticalSyncObserverTokens = [namesToken, sequenceToken, auxiliaryNameToken, auxiliarySequenceToken]
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let signature = SelectionSignature(
                stringLength: textView.string.utf16.count,
                ranges: textView.selectedRanges.map { $0.rangeValue }
            )
            guard signature != lastSelectionSignature else { return }
            lastSelectionSignature = signature

            pendingSelectionUpdate?.cancel()
            let workItem = DispatchWorkItem { [weak self, weak textView] in
                guard let self, let textView else { return }
                self.updateSelectedResidueCount(in: textView)
            }
            pendingSelectionUpdate = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.016, execute: workItem)
        }

        func updateSelectedResidueCount(in textView: NSTextView) {
            guard let textStorage = textView.textStorage else {
                selectedResidueCount.wrappedValue = 0
                selectedStartPosition.wrappedValue = nil
                selectedEndPosition.wrappedValue = nil
                return
            }

            let alignmentLength = (textView as? AlignmentSequenceTextView)?.alignmentLength ?? 0
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
            for selectedRangeValue in textView.selectedRanges {
                let range = selectedRangeValue.rangeValue
                guard range.length > 0 else { continue }

                let rangeEnd = NSMaxRange(range)
                var cursor = range.location
                while cursor < rangeEnd {
                    var effectiveRange = NSRange(location: 0, length: 0)
                    let value = textStorage.attribute(
                        .residueSymbol,
                        at: cursor,
                        longestEffectiveRange: &effectiveRange,
                        in: range
                    )
                    let step = max(effectiveRange.length, 1)
                    defer { cursor = min(rangeEnd, effectiveRange.location + step) }
                    guard let isResidue = value as? Bool, isResidue else { continue }

                    let overlapStart = max(effectiveRange.location, range.location)
                    let overlapEnd = min(NSMaxRange(effectiveRange), rangeEnd)
                    guard overlapEnd > overlapStart else { continue }

                    let overlapLength = overlapEnd - overlapStart
                    count += overlapLength

                    let startColumn = (overlapStart % lineSpan) + 1
                    let endColumn = ((overlapEnd - 1) % lineSpan) + 1
                    minPosition = minPosition.map { min($0, startColumn) } ?? startColumn
                    maxPosition = maxPosition.map { max($0, endColumn) } ?? endColumn
                }
            }
            selectedResidueCount.wrappedValue = count
            selectedStartPosition.wrappedValue = minPosition
            selectedEndPosition.wrappedValue = maxPosition
        }

        private func syncVerticalOffset(from source: NSScrollView, to destination: NSScrollView) {
            guard !isSyncingScroll else { return }
            let sourceY = source.contentView.bounds.origin.y
            var destinationOrigin = destination.contentView.bounds.origin
            guard abs(destinationOrigin.y - sourceY) > scrollEpsilon else { return }
            isSyncingScroll = true
            destinationOrigin.y = sourceY
            destination.contentView.scroll(to: destinationOrigin)
            destination.reflectScrolledClipView(destination.contentView)
            isSyncingScroll = false
        }

        private func syncHorizontalOffset(from source: NSScrollView, to destination: NSScrollView) {
            guard !isSyncingScroll else { return }
            let sourceX = source.contentView.bounds.origin.x
            var destinationOrigin = destination.contentView.bounds.origin
            guard abs(destinationOrigin.x - sourceX) > scrollEpsilon else { return }
            isSyncingScroll = true
            destinationOrigin.x = sourceX
            destination.contentView.scroll(to: destinationOrigin)
            destination.reflectScrolledClipView(destination.contentView)
            isSyncingScroll = false
        }

        private struct SelectionSignature: Equatable {
            let stringLength: Int
            let ranges: [NSRange]
        }
    }
}

final class AlignmentNameTextView: NSTextView {
    var rowNames: [String] = []
    var onSetReference: ((String?) -> Void)?

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let layoutManager, let textContainer else { return super.menu(for: event) }

        let pointInView = convert(event.locationInWindow, from: nil)
        let pointInText = NSPoint(
            x: pointInView.x - textContainerInset.width,
            y: pointInView.y - textContainerInset.height
        )

        let glyphIndex = layoutManager.glyphIndex(for: pointInText, in: textContainer)
        let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        let line = (string as NSString).substring(to: min(charIndex, string.count)).filter { $0 == "\n" }.count
        guard line >= 0, line < rowNames.count else { return super.menu(for: event) }

        let name = rowNames[line]
        let menu = NSMenu(title: "Reference")

        let setItem = NSMenuItem(title: "Set as Reference", action: #selector(setReferenceFromMenu(_:)), keyEquivalent: "")
        setItem.target = self
        setItem.representedObject = name
        menu.addItem(setItem)

        let clearItem = NSMenuItem(title: "Clear Reference", action: #selector(clearReferenceFromMenu(_:)), keyEquivalent: "")
        clearItem.target = self
        menu.addItem(clearItem)

        return menu
    }

    @objc private func setReferenceFromMenu(_ sender: NSMenuItem) {
        onSetReference?(sender.representedObject as? String)
    }

    @objc private func clearReferenceFromMenu(_ sender: NSMenuItem) {
        onSetReference?(nil)
    }
}

final class AlignmentContainerView: NSView, NSSplitViewDelegate {
    private static let minimumNameWidth: CGFloat = 90
    private static let minimumSequenceWidth: CGFloat = 140
    private static let defaultNameWidth: CGFloat = 180
    private static let nameWidthDefaultsKey = "alignmentNameColumnWidth"
    private static let scrollSyncEpsilon: CGFloat = 0.5

    let namesScrollView: NSScrollView
    let sequenceScrollView: NSScrollView
    let namesTextView: AlignmentNameTextView
    let sequenceTextView: AlignmentSequenceTextView
    let rulerView: AlignmentHorizontalRulerView

    let auxiliaryNameScrollView: NSScrollView
    let auxiliarySequenceScrollView: NSScrollView
    let auxiliaryNameTextView: NSTextView
    let auxiliarySequenceTextView: NSTextView
    var onSetReference: ((String?) -> Void)?

    private let splitView: NSSplitView
    private let leftPane: NSView
    private let rightPane: NSView

    private let leftStack: NSStackView
    private let rightStack: NSStackView
    private let leftMainHost: NSView
    private let rightMainHost: NSView
    private let leftAuxHost: NSView
    private let rightAuxHost: NSView
    private let leftHeaderSpacer: NSView
    private let rulerHostView: NSView

    private var leftAuxHeightConstraint: NSLayoutConstraint?
    private var rightAuxHeightConstraint: NSLayoutConstraint?
    private var desiredNameWidth: CGFloat = AlignmentContainerView.defaultNameWidth
    private var lastAppliedNameWidth: CGFloat = -1
    private var lastNotifiedNameWidth: CGFloat = -1
    private var hasInitializedNameWidth = false
    private var lastAuxiliaryFingerprint = AuxiliaryFingerprint.empty
    private var didSetInitialFirstResponder = false
    private var lastAppliedUnsavedFilename: String?
    private var cachedAuxiliarySequenceChecksum: UInt64 = 0
    private var cachedAuxiliarySequenceLength: Int = -1
    private var cachedAuxiliaryPlainSequence: NSAttributedString?
    private var cachedAuxiliaryColoredSequence: NSAttributedString?
    private weak var observedWindow: NSWindow?
    private var liveResizeObserverTokens: [NSObjectProtocol] = []
    private var savedSequenceHorizontalOffsetDuringLiveResize: CGFloat?

    init(namesTextView: AlignmentNameTextView, sequenceTextView: AlignmentSequenceTextView) {
        self.namesTextView = namesTextView
        self.sequenceTextView = sequenceTextView

        let namesScrollView = NSScrollView()
        namesScrollView.documentView = namesTextView
        namesScrollView.hasVerticalScroller = true
        namesScrollView.hasHorizontalScroller = true
        namesScrollView.borderType = .noBorder
        namesScrollView.autohidesScrollers = true
        self.namesScrollView = namesScrollView

        let sequenceScrollView = NSScrollView()
        sequenceScrollView.documentView = sequenceTextView
        sequenceScrollView.hasVerticalScroller = true
        sequenceScrollView.hasHorizontalScroller = true
        sequenceScrollView.borderType = .noBorder
        sequenceScrollView.autohidesScrollers = true
        self.sequenceScrollView = sequenceScrollView

        let rulerView = AlignmentHorizontalRulerView(scrollView: sequenceScrollView)
        self.rulerView = rulerView

        let auxiliaryNameTextView = NSTextView(frame: .zero)
        configureAuxiliaryTextView(auxiliaryNameTextView, fontSize: 12)
        self.auxiliaryNameTextView = auxiliaryNameTextView

        let auxiliarySequenceTextView = NSTextView(frame: .zero)
        configureAuxiliaryTextView(auxiliarySequenceTextView, fontSize: 12)
        self.auxiliarySequenceTextView = auxiliarySequenceTextView

        let auxiliaryNameScrollView = NSScrollView()
        auxiliaryNameScrollView.documentView = auxiliaryNameTextView
        auxiliaryNameScrollView.hasHorizontalScroller = true
        auxiliaryNameScrollView.hasVerticalScroller = false
        auxiliaryNameScrollView.borderType = .noBorder
        auxiliaryNameScrollView.autohidesScrollers = true
        self.auxiliaryNameScrollView = auxiliaryNameScrollView

        let auxiliarySequenceScrollView = NSScrollView()
        auxiliarySequenceScrollView.documentView = auxiliarySequenceTextView
        auxiliarySequenceScrollView.hasHorizontalScroller = true
        auxiliarySequenceScrollView.hasVerticalScroller = false
        auxiliarySequenceScrollView.borderType = .noBorder
        auxiliarySequenceScrollView.autohidesScrollers = true
        self.auxiliarySequenceScrollView = auxiliarySequenceScrollView

        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.translatesAutoresizingMaskIntoConstraints = false
        self.splitView = splitView

        self.leftPane = NSView()
        self.rightPane = NSView()

        let leftStack = NSStackView()
        leftStack.orientation = .vertical
        leftStack.spacing = 0
        leftStack.translatesAutoresizingMaskIntoConstraints = false
        self.leftStack = leftStack

        let rightStack = NSStackView()
        rightStack.orientation = .vertical
        rightStack.spacing = 0
        rightStack.translatesAutoresizingMaskIntoConstraints = false
        self.rightStack = rightStack

        self.leftMainHost = NSView()
        self.rightMainHost = NSView()
        self.leftAuxHost = NSView()
        self.rightAuxHost = NSView()
        self.leftHeaderSpacer = NSView()
        self.rulerHostView = NSView()

        super.init(frame: .zero)
        splitView.delegate = self
        setupLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    deinit {
        removeLiveResizeObservers()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installLiveResizeObserversIfNeeded()
        applyInitialFirstResponderIfNeeded()
    }

    override func setFrameSize(_ newSize: NSSize) {
        let oldWidth = frame.size.width
        super.setFrameSize(newSize)
        guard abs(oldWidth - newSize.width) > 0.5 else { return }
        applySplitPosition()
    }

    func updateMode(nameColumnWidth: CGFloat) {
        let persisted = UserDefaults.standard.double(forKey: Self.nameWidthDefaultsKey)
        let baseWidth: CGFloat
        if !hasInitializedNameWidth {
            hasInitializedNameWidth = true
            baseWidth = persisted > 0 ? CGFloat(persisted) : nameColumnWidth
        } else {
            baseWidth = desiredNameWidth
        }
        let clamped = max(baseWidth, Self.minimumNameWidth)
        guard abs(lastAppliedNameWidth - clamped) > 0.5 else { return }
        desiredNameWidth = clamped
        lastAppliedNameWidth = clamped
        applySplitPosition()
    }

    func updateIdentityShading(alignmentLength: Int, identityByColumn: [Double], isEnabled: Bool) {
        sequenceTextView.alignmentLength = alignmentLength
        sequenceTextView.identityByColumn = identityByColumn
        sequenceTextView.showsIdentityShading = isEnabled
    }

    func updateRuler(alignmentLength: Int, fontSize: Double) {
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        rulerView.update(length: alignmentLength, font: font, textInset: sequenceTextView.textContainerInset.width)
    }

    func syncRulerHorizontalOffsetToSequence() {
        rulerView.needsDisplay = true
    }

    func syncAuxiliaryHorizontalOffsetToSequence() {
        syncHorizontalOffset(
            from: namesScrollView,
            to: auxiliaryNameScrollView,
            epsilon: Self.scrollSyncEpsilon
        )
        syncHorizontalOffset(
            from: sequenceScrollView,
            to: auxiliarySequenceScrollView,
            epsilon: Self.scrollSyncEpsilon
        )
    }

    func updateAuxiliaryPanel(
        nameText: NSAttributedString,
        sequenceText: NSAttributedString,
        lineCount: Int,
        fontSize: Double,
        showsResidueColors: Bool
    ) {
        let fingerprint = AuxiliaryFingerprint(
            nameChecksum: checksum(for: nameText.string),
            sequenceChecksum: checksum(for: sequenceText.string),
            lineCount: lineCount,
            fontSize: fontSize,
            showsResidueColors: showsResidueColors
        )
        if fingerprint == lastAuxiliaryFingerprint {
            return
        }
        lastAuxiliaryFingerprint = fingerprint

        auxiliaryNameTextView.textStorage?.setAttributedString(nameText)
        let sequenceChecksum = fingerprint.sequenceChecksum
        let sequenceLength = sequenceText.length
        if sequenceChecksum != cachedAuxiliarySequenceChecksum || sequenceLength != cachedAuxiliarySequenceLength {
            cachedAuxiliarySequenceChecksum = sequenceChecksum
            cachedAuxiliarySequenceLength = sequenceLength
            cachedAuxiliaryColoredSequence = nil
            cachedAuxiliaryPlainSequence = makePlainAuxiliarySequence(from: sequenceText)
        }

        if showsResidueColors {
            if cachedAuxiliaryColoredSequence == nil, let plain = cachedAuxiliaryPlainSequence {
                let mutable = NSMutableAttributedString(attributedString: plain)
                applyResidueColorsToAuxiliaryText(mutable)
                cachedAuxiliaryColoredSequence = mutable.copy() as? NSAttributedString
            }
            auxiliarySequenceTextView.textStorage?.setAttributedString(
                cachedAuxiliaryColoredSequence ?? cachedAuxiliaryPlainSequence ?? NSAttributedString(string: "")
            )
        } else {
            auxiliarySequenceTextView.textStorage?.setAttributedString(
                cachedAuxiliaryPlainSequence ?? makePlainAuxiliarySequence(from: sequenceText)
            )
        }

        let mono = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        auxiliaryNameTextView.font = mono
        auxiliarySequenceTextView.font = mono

        // Force layout/document size refresh so text becomes visible immediately after panel height changes.
        auxiliaryNameTextView.layoutManager?.ensureLayout(for: auxiliaryNameTextView.textContainer!)
        auxiliarySequenceTextView.layoutManager?.ensureLayout(for: auxiliarySequenceTextView.textContainer!)
        auxiliaryNameTextView.sizeToFit()
        auxiliarySequenceTextView.sizeToFit()

        let lineHeight = mono.ascender - mono.descender + 2
        let targetHeight = lineCount > 0 ? max(CGFloat(lineCount) * lineHeight + 10, 24) : 0

        let showsAuxiliary = lineCount > 0
        leftAuxHeightConstraint?.constant = targetHeight
        rightAuxHeightConstraint?.constant = targetHeight
        leftAuxHost.isHidden = !showsAuxiliary
        rightAuxHost.isHidden = !showsAuxiliary

        // Keep horizontal scrollers only at the very bottom when auxiliary panel is visible.
        namesScrollView.hasHorizontalScroller = !showsAuxiliary
        sequenceScrollView.hasHorizontalScroller = !showsAuxiliary
        auxiliaryNameScrollView.hasHorizontalScroller = showsAuxiliary
        auxiliarySequenceScrollView.hasHorizontalScroller = showsAuxiliary
    }

    func updateNameRows(_ names: [String]) {
        namesTextView.rowNames = names
        namesTextView.onSetReference = onSetReference
    }

    func updatePreferredUnsavedFilename(_ filename: String?) {
        guard filename != lastAppliedUnsavedFilename else { return }
        guard let filename, !filename.isEmpty else { return }
        guard let window else { return }
        guard window.representedURL == nil else { return }
        window.title = filename
        lastAppliedUnsavedFilename = filename
    }

    private func makePlainAuxiliarySequence(from source: NSAttributedString) -> NSAttributedString {
        let mutable = NSMutableAttributedString(attributedString: source)
        let fullRange = NSRange(location: 0, length: mutable.length)
        mutable.removeAttribute(.foregroundColor, range: fullRange)
        mutable.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: fullRange)
        return mutable.copy() as? NSAttributedString ?? NSAttributedString(string: mutable.string)
    }

    private func applyResidueColorsToAuxiliaryText(_ attributed: NSMutableAttributedString) {
        let text = attributed.string as NSString
        guard text.length > 0 else { return }

        var runStart = 0
        var currentColor = ResiduePalette.color(for: text.character(at: 0))

        for index in 1...text.length {
            let nextColor: NSColor?
            if index < text.length {
                nextColor = ResiduePalette.color(for: text.character(at: index))
            } else {
                nextColor = nil
            }

            if nextColor == currentColor { continue }
            if let color = currentColor {
                attributed.addAttribute(
                    .foregroundColor,
                    value: color,
                    range: NSRange(location: runStart, length: index - runStart)
                )
            }
            runStart = index
            currentColor = nextColor
        }
    }

    private func checksum(for text: String) -> UInt64 {
        var hasher = Hasher()
        hasher.combine(text)
        return UInt64(bitPattern: Int64(hasher.finalize()))
    }

    private func syncHorizontalOffset(from source: NSScrollView, to destination: NSScrollView, epsilon: CGFloat) {
        let sourceX = source.contentView.bounds.origin.x
        var destinationOrigin = destination.contentView.bounds.origin
        guard abs(destinationOrigin.x - sourceX) > epsilon else { return }
        destinationOrigin.x = sourceX
        destination.contentView.scroll(to: destinationOrigin)
        destination.reflectScrolledClipView(destination.contentView)
    }

    private func installLiveResizeObserversIfNeeded() {
        guard observedWindow !== window else { return }
        removeLiveResizeObservers()
        guard let window else { return }

        observedWindow = window

        let willStartToken = NotificationCenter.default.addObserver(
            forName: NSWindow.willStartLiveResizeNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.savedSequenceHorizontalOffsetDuringLiveResize =
                self.sequenceScrollView.contentView.bounds.origin.x
        }

        let didEndToken = NotificationCenter.default.addObserver(
            forName: NSWindow.didEndLiveResizeNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            guard let savedX = self.savedSequenceHorizontalOffsetDuringLiveResize else { return }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                var origin = self.sequenceScrollView.contentView.bounds.origin
                origin.x = savedX
                self.sequenceScrollView.contentView.scroll(to: origin)
                self.sequenceScrollView.reflectScrolledClipView(self.sequenceScrollView.contentView)
                self.syncAuxiliaryHorizontalOffsetToSequence()
                self.syncRulerHorizontalOffsetToSequence()
            }
        }

        liveResizeObserverTokens = [willStartToken, didEndToken]
    }

    private func removeLiveResizeObservers() {
        for token in liveResizeObserverTokens {
            NotificationCenter.default.removeObserver(token)
        }
        liveResizeObserverTokens.removeAll()
        observedWindow = nil
    }

    private func setupLayout() {
        addSubview(splitView)
        NSLayoutConstraint.activate([
            splitView.leadingAnchor.constraint(equalTo: leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: trailingAnchor),
            splitView.topAnchor.constraint(equalTo: topAnchor),
            splitView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        [
            leftPane, rightPane,
            leftStack, rightStack,
            leftMainHost, rightMainHost,
            leftAuxHost, rightAuxHost,
            leftHeaderSpacer, rulerHostView,
            namesScrollView, sequenceScrollView,
            auxiliaryNameScrollView, auxiliarySequenceScrollView,
            rulerView
        ].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }

        splitView.addArrangedSubview(leftPane)
        splitView.addArrangedSubview(rightPane)

        leftPane.addSubview(leftStack)
        rightPane.addSubview(rightStack)

        NSLayoutConstraint.activate([
            leftStack.leadingAnchor.constraint(equalTo: leftPane.leadingAnchor),
            leftStack.trailingAnchor.constraint(equalTo: leftPane.trailingAnchor),
            leftStack.topAnchor.constraint(equalTo: leftPane.topAnchor),
            leftStack.bottomAnchor.constraint(equalTo: leftPane.bottomAnchor),

            rightStack.leadingAnchor.constraint(equalTo: rightPane.leadingAnchor),
            rightStack.trailingAnchor.constraint(equalTo: rightPane.trailingAnchor),
            rightStack.topAnchor.constraint(equalTo: rightPane.topAnchor),
            rightStack.bottomAnchor.constraint(equalTo: rightPane.bottomAnchor)
        ])

        leftStack.addArrangedSubview(leftMainHost)
        leftStack.addArrangedSubview(leftAuxHost)
        rightStack.addArrangedSubview(rightMainHost)
        rightStack.addArrangedSubview(rightAuxHost)

        leftAuxHeightConstraint = leftAuxHost.heightAnchor.constraint(equalToConstant: 0)
        rightAuxHeightConstraint = rightAuxHost.heightAnchor.constraint(equalToConstant: 0)
        leftAuxHeightConstraint?.isActive = true
        rightAuxHeightConstraint?.isActive = true
        leftAuxHost.isHidden = true
        rightAuxHost.isHidden = true

        leftMainHost.addSubview(leftHeaderSpacer)
        leftMainHost.addSubview(namesScrollView)
        rightMainHost.addSubview(rulerHostView)
        rightMainHost.addSubview(sequenceScrollView)
        rulerHostView.addSubview(rulerView)

        leftAuxHost.addSubview(auxiliaryNameScrollView)
        rightAuxHost.addSubview(auxiliarySequenceScrollView)

        NSLayoutConstraint.activate([
            leftHeaderSpacer.leadingAnchor.constraint(equalTo: leftMainHost.leadingAnchor),
            leftHeaderSpacer.trailingAnchor.constraint(equalTo: leftMainHost.trailingAnchor),
            leftHeaderSpacer.topAnchor.constraint(equalTo: leftMainHost.topAnchor),
            leftHeaderSpacer.heightAnchor.constraint(equalToConstant: AlignmentHorizontalRulerView.rulerHeight),

            namesScrollView.leadingAnchor.constraint(equalTo: leftMainHost.leadingAnchor),
            namesScrollView.trailingAnchor.constraint(equalTo: leftMainHost.trailingAnchor),
            namesScrollView.topAnchor.constraint(equalTo: leftHeaderSpacer.bottomAnchor),
            namesScrollView.bottomAnchor.constraint(equalTo: leftMainHost.bottomAnchor),

            rulerHostView.leadingAnchor.constraint(equalTo: rightMainHost.leadingAnchor),
            rulerHostView.trailingAnchor.constraint(equalTo: rightMainHost.trailingAnchor),
            rulerHostView.topAnchor.constraint(equalTo: rightMainHost.topAnchor),
            rulerHostView.heightAnchor.constraint(equalToConstant: AlignmentHorizontalRulerView.rulerHeight),

            sequenceScrollView.leadingAnchor.constraint(equalTo: rightMainHost.leadingAnchor),
            sequenceScrollView.trailingAnchor.constraint(equalTo: rightMainHost.trailingAnchor),
            sequenceScrollView.topAnchor.constraint(equalTo: rulerHostView.bottomAnchor),
            sequenceScrollView.bottomAnchor.constraint(equalTo: rightMainHost.bottomAnchor),

            rulerView.leadingAnchor.constraint(equalTo: rulerHostView.leadingAnchor),
            rulerView.trailingAnchor.constraint(equalTo: rulerHostView.trailingAnchor),
            rulerView.topAnchor.constraint(equalTo: rulerHostView.topAnchor),
            rulerView.bottomAnchor.constraint(equalTo: rulerHostView.bottomAnchor),

            auxiliaryNameScrollView.leadingAnchor.constraint(equalTo: leftAuxHost.leadingAnchor),
            auxiliaryNameScrollView.trailingAnchor.constraint(equalTo: leftAuxHost.trailingAnchor),
            auxiliaryNameScrollView.topAnchor.constraint(equalTo: leftAuxHost.topAnchor),
            auxiliaryNameScrollView.bottomAnchor.constraint(equalTo: leftAuxHost.bottomAnchor),

            auxiliarySequenceScrollView.leadingAnchor.constraint(equalTo: rightAuxHost.leadingAnchor),
            auxiliarySequenceScrollView.trailingAnchor.constraint(equalTo: rightAuxHost.trailingAnchor),
            auxiliarySequenceScrollView.topAnchor.constraint(equalTo: rightAuxHost.topAnchor),
            auxiliarySequenceScrollView.bottomAnchor.constraint(equalTo: rightAuxHost.bottomAnchor)
        ])

        splitView.adjustSubviews()
        applySplitPosition()
    }

    private func applyInitialFirstResponderIfNeeded() {
        guard !didSetInitialFirstResponder else { return }
        guard let window else { return }
        guard sequenceTextView.acceptsFirstResponder else { return }
        didSetInitialFirstResponder = true
        DispatchQueue.main.async { [weak window, weak sequenceTextView] in
            guard let window, let sequenceTextView else { return }
            _ = window.makeFirstResponder(sequenceTextView)
        }
    }

    private func applySplitPosition() {
        guard splitView.subviews.count >= 2 else { return }
        let maxAllowed = max(Self.minimumNameWidth, bounds.width - splitView.dividerThickness - Self.minimumSequenceWidth)
        let clamped = min(max(desiredNameWidth, Self.minimumNameWidth), maxAllowed)
        let current = splitView.subviews[0].frame.width
        if abs(current - clamped) > 0.5 {
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
        guard window?.inLiveResize != true else { return }
        guard abs(lastNotifiedNameWidth - desiredNameWidth) > 0.5 else { return }
        lastNotifiedNameWidth = desiredNameWidth
        UserDefaults.standard.set(Double(desiredNameWidth), forKey: Self.nameWidthDefaultsKey)
    }

    func splitView(_ splitView: NSSplitView, shouldAdjustSizeOfSubview view: NSView) -> Bool {
        view !== leftPane
    }
}

private struct AuxiliaryFingerprint: Equatable {
    let nameChecksum: UInt64
    let sequenceChecksum: UInt64
    let lineCount: Int
    let fontSize: Double
    let showsResidueColors: Bool

    static let empty = AuxiliaryFingerprint(
        nameChecksum: 0,
        sequenceChecksum: 0,
        lineCount: -1,
        fontSize: -1,
        showsResidueColors: false
    )
}

final class AlignmentSequenceTextView: NSTextView {
    var alignmentLength: Int = 0 {
        didSet { needsDisplay = true }
    }
    var identityByColumn: [Double] = [] {
        didSet { needsDisplay = true }
    }
    var showsIdentityShading: Bool = false {
        didSet { needsDisplay = true }
    }
    private var cachedIdentityColors: [NSColor] = []
    private var cachedIdentityChecksum: UInt64 = 0

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)

        guard
            showsIdentityShading,
            alignmentLength > 0,
            !identityByColumn.isEmpty,
            let layoutManager,
            let textContainer
        else {
            return
        }
        ensureIdentityColorCache()

        let glyphRange = layoutManager.glyphRange(forBoundingRect: rect, in: textContainer)
        let characterRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        guard characterRange.length > 0 else { return }

        let lineSpan = alignmentLength + 1
        let maxCharacter = characterRange.location + characterRange.length

        var runStart: Int?
        var runEnd = 0
        var runColor: NSColor?

        func flushRun() {
            guard
                let runStart,
                let runColor,
                runEnd > runStart
            else {
                return
            }
            let runRange = NSRange(location: runStart, length: runEnd - runStart)
            let runGlyphRange = layoutManager.glyphRange(forCharacterRange: runRange, actualCharacterRange: nil)
            var drawRect = layoutManager.boundingRect(forGlyphRange: runGlyphRange, in: textContainer)
            drawRect.origin.x += textContainerOrigin.x
            drawRect.origin.y += textContainerOrigin.y
            runColor.setFill()
            drawRect.fill()
        }

        for index in characterRange.location..<maxCharacter {
            let column = index % lineSpan
            if column >= alignmentLength {
                flushRun()
                runStart = nil
                runColor = nil
                runEnd = index
                continue
            }

            guard let color = cachedIdentityColors[safe: column] else {
                continue
            }
            if runStart == nil {
                runStart = index
                runEnd = index + 1
                runColor = color
                continue
            }

            if color == runColor, runEnd == index {
                runEnd = index + 1
            } else {
                flushRun()
                runStart = index
                runEnd = index + 1
                runColor = color
            }
        }
        flushRun()
    }

    private func ensureIdentityColorCache() {
        let checksum = identityByColumn.reduce(into: UInt64(1469598103934665603)) { partialResult, value in
            partialResult = (partialResult ^ UInt64(bitPattern: Int64(value.bitPattern))) &* 1099511628211
        }
        guard checksum != cachedIdentityChecksum || cachedIdentityColors.count != identityByColumn.count else { return }
        cachedIdentityChecksum = checksum
        cachedIdentityColors = identityByColumn.map { IdentityPalette.backgroundColor(for: $0) }
    }
}

final class AlignmentHorizontalRulerView: NSRulerView {
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
        ruleThickness = Self.rulerHeight
        needsDisplay = true
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        rect.fill()

        guard alignmentLength > 0 else { return }
        guard let scrollView else { return }

        let glyphWidth = max(characterAdvance, 1)
        let smallFontSize = max(baseFont.pointSize - 4, 7)
        let labelFont = NSFont.monospacedSystemFont(ofSize: smallFontSize, weight: .regular)
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        let visibleRect = scrollView.contentView.bounds
        let visibleStart = max(Int(floor((visibleRect.minX - textInset) / glyphWidth)) + 1, 1)
        let visibleEnd = min(Int(ceil((visibleRect.maxX - textInset) / glyphWidth)) + 1, alignmentLength)
        if visibleStart > visibleEnd { return }

        var tick = ((visibleStart + step - 1) / step) * step
        let labelY: CGFloat = 2
        let tickTopY: CGFloat = 14
        let tickBottomY: CGFloat = 19

        while tick <= visibleEnd {
            let documentX = textInset + (CGFloat(tick - 1) * glyphWidth) + glyphWidth
            let x = documentX - visibleRect.minX
            let markerPath = NSBezierPath()
            markerPath.move(to: NSPoint(x: x, y: tickTopY))
            markerPath.line(to: NSPoint(x: x, y: tickBottomY))
            NSColor.tertiaryLabelColor.setStroke()
            markerPath.lineWidth = 1
            markerPath.stroke()

            let label = "\(tick)" as NSString
            let labelSize = label.size(withAttributes: labelAttributes)
            label.draw(
                at: NSPoint(x: x - (labelSize.width / 2), y: labelY),
                withAttributes: labelAttributes
            )
            tick += step
        }
    }

    private var characterAdvance: CGFloat {
        let sample = "M" as NSString
        return sample.size(withAttributes: [.font: baseFont]).width
    }
}
