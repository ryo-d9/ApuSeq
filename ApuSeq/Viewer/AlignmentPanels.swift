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
                    label: String(localized: "Columns"),
                    value: "\(selectedStartPosition)-\(selectedEndPosition)",
                    identifier: "alignment-column-selection"
                )
            }
            Spacer()
            Picker(String(localized: "Background"), selection: $backgroundMode) {
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
    let sequenceCount: Int
    let residueCount: Int
    let sourceCharacterCount: Int

    var body: some View {
        List {
            LabeledContent(String(localized: "Format"), value: format)
            LabeledContent(String(localized: "Sequences"), value: "\(sequenceCount)")
            LabeledContent(String(localized: "Residues"), value: "\(residueCount)")
            LabeledContent(String(localized: "Source Chars"), value: "\(sourceCharacterCount)")
        }
        .navigationTitle(String(localized: "Information"))
    }
}
