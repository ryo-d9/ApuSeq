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
}

struct AlignmentEditActions {
    let canRemoveAllGapColumns: Bool
    let removeAllGapColumns: () -> Void
}

enum AppAppearanceMode: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
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
                _ = NSApp.sendAction(NSSelectorFromString("selectColumnUp:"), to: nil, from: nil)
            }
            .keyboardShortcut(.upArrow, modifiers: [.control, .shift])

            Button("Select Column Down") {
                _ = NSApp.sendAction(NSSelectorFromString("selectColumnDown:"), to: nil, from: nil)
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
            .keyboardShortcut(.delete, modifiers: [.command, .shift])
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
    @AppStorage("appearanceMode") private var appearanceMode = AppAppearanceMode.system.rawValue
    @AppStorage("showEditModeAutosaveWarning") private var showEditModeAutosaveWarning = true

    var body: some View {
        TabView {
            generalSettings
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            appearanceSettings
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }

            editingSettings
                .tabItem {
                    Label("Editing", systemImage: "pencil")
                }
        }
        .padding(20)
        .frame(width: 500, height: 280)
        .preferredColorScheme((AppAppearanceMode(rawValue: appearanceMode) ?? .system).colorScheme)
    }

    private var generalSettings: some View {
        Form {
            Section("Alignment") {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("Font Size") {
                        HStack {
                            Slider(value: $alignmentFontSize, in: 8...24, step: 1)
                                .frame(width: 220)
                            Text("\(Int(alignmentFontSize)) pt")
                                .frame(width: 56, alignment: .trailing)
                                .monospacedDigit()
                        }
                    }

                    LabeledContent("Identity Threshold") {
                        HStack {
                            Slider(value: $identityColorThreshold, in: 0.1...0.9, step: 0.01)
                                .frame(width: 220)
                            Text("\(Int(identityColorThreshold * 100))%")
                                .frame(width: 56, alignment: .trailing)
                                .monospacedDigit()
                        }
                    }
                }
            }

            Section("Translation") {
                Picker("Codon Table", selection: $translationCodonTable) {
                    ForEach(TranslationCodonTable.allCases) { table in
                        Text(table.displayName).tag(table.rawValue)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .formStyle(.grouped)
    }

    private var appearanceSettings: some View {
        Form {
            Section("Appearance") {
                Picker("Appearance", selection: $appearanceMode) {
                    ForEach(AppAppearanceMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.menu)

                Text("Choose whether ApuSeq follows the system appearance or uses a fixed light or dark appearance.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var editingSettings: some View {
        Form {
            Section("Edit Mode") {
                Toggle("Edit Mode Warning", isOn: $showEditModeAutosaveWarning)

                Text("Show a warning before entering Edit mode because edits can be autosaved with document versions.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
