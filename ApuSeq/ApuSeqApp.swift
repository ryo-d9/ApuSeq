//
//  ApuSeqApp.swift
//  ApuSeq
//
//  Created by 須田崚 on 2026/04/27.
//

import AppKit
import SwiftUI

struct TranslationContext {
    let rawText: String
    let sequenceKind: SequenceKind
    let fileBaseName: String
    let sourceDirectoryURL: URL?
}

struct AlignmentEditActions {
    let canRemoveAllGapColumns: Bool
    let removeAllGapColumns: () -> Void
}

private struct TranslationContextKey: FocusedValueKey {
    typealias Value = TranslationContext
}

private struct AlignmentEditActionsKey: FocusedValueKey {
    typealias Value = AlignmentEditActions
}

extension FocusedValues {
    var translationContext: TranslationContext? {
        get { self[TranslationContextKey.self] }
        set { self[TranslationContextKey.self] = newValue }
    }

    var alignmentEditActions: AlignmentEditActions? {
        get { self[AlignmentEditActionsKey.self] }
        set { self[AlignmentEditActionsKey.self] = newValue }
    }
}

@main
struct ApuSeqApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: { ApuSeqDocument() }) { file in
            ContentView(document: file.document)
        }
        .commands {
            FindCommands()
            TranslationCommands()
            ViewPanelCommands()
            ColumnSelectionCommands()
            AlignmentEditCommands()
        }

        Settings {
            AppSettingsView()
        }
    }
}

private struct FindCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Find") {
                FindActionDispatcher.perform(.showFindInterface)
            }
            .keyboardShortcut("f", modifiers: .command)

            Button("Find Next") {
                FindActionDispatcher.perform(.nextMatch)
            }
            .keyboardShortcut("g", modifiers: .command)

            Button("Find Previous") {
                FindActionDispatcher.perform(.previousMatch)
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])
        }
    }
}

private struct ColumnSelectionCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Divider()
            Button("Select Column Up") {
                _ = NSApp.sendAction(Selector(("selectColumnUp:")), to: nil, from: nil)
            }
            .keyboardShortcut(.upArrow, modifiers: [.control, .shift])

            Button("Select Column Down") {
                _ = NSApp.sendAction(Selector(("selectColumnDown:")), to: nil, from: nil)
            }
            .keyboardShortcut(.downArrow, modifiers: [.control, .shift])
        }
    }
}

private struct AlignmentEditCommands: Commands {
    @FocusedValue(\.alignmentEditActions) private var actions

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Button("Remove All-Gap Columns") {
                actions?.removeAllGapColumns()
            }
            .disabled(actions?.canRemoveAllGapColumns != true)
        }
    }
}

private struct ViewPanelCommands: Commands {
    @AppStorage("showReferencePanel") private var showReferencePanel = false
    @AppStorage("showConsensusPanel") private var showConsensusPanel = false
    @AppStorage("showConservationPanel") private var showConservationPanel = false

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Divider()
            Toggle(showReferencePanel ? "Hide Reference Panel" : "Show Reference Panel", isOn: $showReferencePanel)
            Toggle(showConsensusPanel ? "Hide Consensus Panel" : "Show Consensus Panel", isOn: $showConsensusPanel)
            Toggle(showConservationPanel ? "Hide Identity Panel" : "Show Identity Panel", isOn: $showConservationPanel)
        }
    }
}

private enum FindActionDispatcher {
    static func perform(_ action: NSTextFinder.Action) {
        let item = NSMenuItem()
        item.tag = action.rawValue
        NSApp.sendAction(#selector(NSResponder.performTextFinderAction(_:)), to: nil, from: item)
    }
}

private struct TranslationCommands: Commands {
    @FocusedValue(\.translationContext) private var context
    @Environment(\.newDocument) private var newDocument
    @AppStorage("translationCodonTable") private var translationCodonTable = TranslationCodonTable.standard.rawValue

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Menu("Translation") {
                Button("Frame +0") { runTranslation(frameOffset: 0) }
                    .keyboardShortcut("0", modifiers: [.command, .option])
                Button("Frame +1") { runTranslation(frameOffset: 1) }
                Button("Frame +2") { runTranslation(frameOffset: 2) }
            }
            .disabled(!canTranslate)
        }
    }

    private var canTranslate: Bool {
        guard let context else { return false }
        return context.sequenceKind == .nucleotide && !context.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func runTranslation(frameOffset: Int) {
        guard let context else { return }
        let codonTable = TranslationCodonTable(rawValue: translationCodonTable) ?? .standard
        Task {
            do {
                let translated = try AlignmentTranslator.translateFASTA(
                    rawText: context.rawText,
                    frameOffset: frameOffset,
                    codonTable: codonTable
                )
                await MainActor.run {
                    newDocument {
                        ApuSeqDocument(
                            rawText: translated,
                            suggestedSaveFilename: "\(context.fileBaseName)_translated",
                            markEditedOnFirstDisplay: true
                        )
                    }
                }
            } catch {
                NSSound.beep()
            }
        }
    }
}

private struct AppSettingsView: View {
    @AppStorage("alignmentFontSize") private var alignmentFontSize = 12.0
    @AppStorage("identityColorThreshold") private var identityColorThreshold = 0.5
    @AppStorage("translationCodonTable") private var translationCodonTable = TranslationCodonTable.standard.rawValue

    var body: some View {
        Form {
            VStack(alignment: .leading, spacing: 8) {
                Text("Alignment Font Size")
                HStack {
                    Slider(value: $alignmentFontSize, in: 8...24, step: 1)
                    Text("\(Int(alignmentFontSize)) pt")
                        .frame(width: 56, alignment: .trailing)
                        .monospacedDigit()
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Identity Threshold")
                HStack {
                    Slider(value: $identityColorThreshold, in: 0.1...0.9, step: 0.01)
                    Text("\(Int(identityColorThreshold * 100))%")
                        .frame(width: 56, alignment: .trailing)
                        .monospacedDigit()
                }
            }
            Picker("Translation Codon Table", selection: $translationCodonTable) {
                ForEach(TranslationCodonTable.allCases) { table in
                    Text(table.displayName).tag(table.rawValue)
                }
            }
        }
        .padding(16)
        .frame(width: 360)
    }
}
