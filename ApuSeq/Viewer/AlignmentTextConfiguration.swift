import AppKit

private let alignmentLineHeightLayoutManager = NSLayoutManager()

func alignmentLineHeight(for font: NSFont) -> CGFloat {
    max(alignmentLineHeightLayoutManager.defaultLineHeight(for: font), 1)
}

func configureMainTextView(_ textView: NSTextView, fontSize: Double) {
    textView.isEditable = false
    textView.isSelectable = true
    textView.allowsUndo = true
    textView.isRichText = false
    textView.usesRuler = false
    textView.usesInspectorBar = false
    textView.usesFontPanel = false
    textView.drawsBackground = true
    textView.backgroundColor = NSColor.textBackgroundColor
    textView.textContainerInset = NSSize(width: 12, height: 12)
    textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    textView.usesFindBar = true
    textView.isIncrementalSearchingEnabled = true
    textView.isContinuousSpellCheckingEnabled = false
    textView.isGrammarCheckingEnabled = false
    textView.isAutomaticSpellingCorrectionEnabled = false
    textView.isAutomaticTextReplacementEnabled = false
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.isHorizontallyResizable = true
    textView.isVerticallyResizable = true
    textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    textView.minSize = NSSize(width: 0, height: 0)
    textView.textContainer?.widthTracksTextView = false
    textView.textContainer?.lineBreakMode = .byClipping
    textView.textContainer?.containerSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
}

func configureNameTextView(_ textView: NSTextView, fontSize: Double) {
    textView.isEditable = false
    textView.isSelectable = false
    textView.isRichText = false
    textView.usesRuler = false
    textView.usesInspectorBar = false
    textView.usesFontPanel = false
    textView.drawsBackground = true
    textView.backgroundColor = NSColor.textBackgroundColor
    textView.textContainerInset = NSSize(width: 12, height: 12)
    textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    textView.isHorizontallyResizable = true
    textView.isVerticallyResizable = true
    textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    textView.minSize = NSSize(width: 0, height: 0)
    textView.textContainer?.widthTracksTextView = false
    textView.textContainer?.lineBreakMode = .byClipping
    textView.textContainer?.containerSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
}

func configureAuxiliaryTextView(_ textView: NSTextView, fontSize: Double) {
    textView.isEditable = false
    textView.isSelectable = false
    textView.isRichText = false
    textView.usesRuler = false
    textView.usesInspectorBar = false
    textView.usesFontPanel = false
    textView.drawsBackground = true
    textView.backgroundColor = NSColor.textBackgroundColor
    textView.textContainerInset = NSSize(width: 12, height: 4)
    textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    textView.isHorizontallyResizable = true
    textView.isVerticallyResizable = true
    textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    textView.minSize = NSSize(width: 0, height: 0)
    textView.textContainer?.widthTracksTextView = false
    textView.textContainer?.heightTracksTextView = false
    textView.textContainer?.lineBreakMode = .byClipping
    textView.textContainer?.containerSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
}
