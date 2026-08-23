import SwiftUI

struct FooterBar: View {
    let sequenceCount: Int
    let residueCount: Int
    let selectedResidueCount: Int
    let selectedSequenceCount: Int
    let selectedStartPosition: Int?
    let selectedEndPosition: Int?
    @Binding var backgroundMode: AlignmentBackgroundMode
    let availableBackgroundModes: [AlignmentBackgroundMode]
    @Binding var displayOrderMode: AlignmentDisplayOrderMode
    let canChangeDisplayOrder: Bool
    let canDisplayUPGMAOrder: Bool

    var body: some View {
        HStack(spacing: 8) {
            statusItem(
                label: String(localized: "Sequences"),
                value: "\(sequenceCount)\(selectedSequenceSuffix)",
                identifier: "alignment-sequence-count"
            )
            statusItem(
                label: String(localized: "Sites"),
                value: "\(residueCount)\(selectedResidueSuffix)",
                identifier: "alignment-site-count"
            )
            if let selectedStartPosition, let selectedEndPosition, selectedResidueCount > 0 {
                statusItem(
                    label: String(localized: "Positions"),
                    value: "\(selectedStartPosition)-\(selectedEndPosition)",
                    identifier: "alignment-column-selection"
                )
            }
            Spacer()
            Picker(String(localized: "Background Color"), selection: $backgroundMode) {
                ForEach(availableBackgroundModes) { mode in
                    Text(mode.localizedName).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .labelsVisibility(.hidden)
            .accessibilityIdentifier("alignment-background-picker")
            .fixedSize()
            .help(String(localized: "Change background coloring"))
            Divider()
            Picker(String(localized: "Display Order"), selection: $displayOrderMode) {
                ForEach(AlignmentDisplayOrderMode.allCases) { mode in
                    Text(mode.localizedName).tag(mode)
                        .disabled(mode == .upgma && !canDisplayUPGMAOrder)
                }
            }
            .pickerStyle(.menu)
            .labelsVisibility(.hidden)
            .accessibilityIdentifier("alignment-display-order-picker")
            .fixedSize()
            .disabled(!canChangeDisplayOrder)
            .help(String(localized: "Change sequence display order in view mode"))
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .lineLimit(1)
        .monospacedDigit()
        .frame(height: 16)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var selectedSequenceSuffix: String {
        selectedSequenceCount > 0 ? " (\(selectedSequenceCount))" : ""
    }

    private var selectedResidueSuffix: String {
        selectedResidueCount > 0 ? " (\(selectedResidueCount))" : ""
    }

    private func statusItem(label: String, value: String, identifier: String) -> some View {
        HStack(spacing: 0) {
            Text("\(label): ")
                .foregroundStyle(.secondary)
            Text(value)
                .foregroundStyle(.primary)
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
        .accessibilityValue(value)
        .accessibilityIdentifier(identifier)
    }
}

struct FileInformationView: View {
    let format: String
    let sequenceKind: String
    let sequenceCount: Int
    let siteCount: Int
    let sourceCharacterCount: Int
    let selectedSequenceCount: Int
    let selectedSiteCount: Int
    let selectedStartPosition: Int?
    let selectedEndPosition: Int?
    let referenceName: String?
    let displayOrder: String
    let background: String

    var body: some View {
        List {
            Section(String(localized: "Document")) {
                LabeledContent(String(localized: "File Format"), value: format)
                LabeledContent(String(localized: "Sequence Type"), value: sequenceKind)
                LabeledContent(String(localized: "Sequences"), value: "\(sequenceCount)")
                LabeledContent(String(localized: "Sites"), value: "\(siteCount)")
                LabeledContent(String(localized: "Total Characters"), value: "\(sourceCharacterCount)")
            }
            Section(String(localized: "Selection")) {
                LabeledContent(String(localized: "Selected Sequences"), value: selectionValue(selectedSequenceCount))
                LabeledContent(String(localized: "Selected Sites"), value: selectionValue(selectedSiteCount))
                LabeledContent(String(localized: "Selected Positions"), value: selectedColumnsValue)
            }
            Section(String(localized: "View")) {
                LabeledContent(String(localized: "Reference Sequence"), value: referenceName ?? String(localized: "None"))
                LabeledContent(String(localized: "Display Order"), value: displayOrder)
                LabeledContent(String(localized: "Background Color"), value: background)
            }
        }
        .navigationTitle(String(localized: "Information"))
    }

    private var selectedColumnsValue: String {
        guard let selectedStartPosition, let selectedEndPosition, selectedSiteCount > 0 else {
            return String(localized: "None")
        }
        return "\(selectedStartPosition)-\(selectedEndPosition)"
    }

    private func selectionValue(_ count: Int) -> String {
        count > 0 ? "\(count)" : String(localized: "None")
    }
}
