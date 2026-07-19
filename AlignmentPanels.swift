import SwiftUI

struct FooterBar: View {
    let sequenceCount: Int
    let residueCount: Int
    let selectedResidueCount: Int
    let selectedSequenceCount: Int
    let selectedStartPosition: Int?
    let selectedEndPosition: Int?
    @Binding var backgroundMode: AlignmentBackgroundMode
    @Binding var displayOrderMode: AlignmentDisplayOrderMode
    let canChangeDisplayOrder: Bool

    var body: some View {
        HStack(spacing: 8) {
            statusItem(label: "Sequences", value: "\(sequenceCount)\(selectedSequenceSuffix)")
            statusItem(label: "Sites", value: "\(residueCount)\(selectedResidueSuffix)")
            if let selectedStartPosition, let selectedEndPosition, selectedResidueCount > 0 {
                statusItem(label: "Columns", value: "\(selectedStartPosition)-\(selectedEndPosition)")
            }
            Spacer()
            Picker("Background", selection: $backgroundMode) {
                ForEach(AlignmentBackgroundMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .labelsVisibility(.hidden)
            .fixedSize()
            .help("Change background coloring")
            Divider()
            Picker("Order", selection: $displayOrderMode) {
                ForEach(AlignmentDisplayOrderMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .labelsVisibility(.hidden)
            .fixedSize()
            .disabled(!canChangeDisplayOrder)
            .help("Change sequence display order in view mode")
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

    private func statusItem(label: String, value: String) -> some View {
        HStack(spacing: 0) {
            Text("\(label): ")
                .foregroundStyle(.secondary)
            Text(value)
                .foregroundStyle(.primary)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct FileInformationView: View {
    let format: String
    let sequenceCount: Int
    let residueCount: Int
    let sourceCharacterCount: Int

    var body: some View {
        List {
            LabeledContent("Format", value: format)
            LabeledContent("Sequences", value: "\(sequenceCount)")
            LabeledContent("Residues", value: "\(residueCount)")
            LabeledContent("Source Chars", value: "\(sourceCharacterCount)")
        }
        .navigationTitle("Information")
    }
}
