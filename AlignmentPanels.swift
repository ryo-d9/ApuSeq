import SwiftUI

struct FooterBar: View {
    let sequenceCount: Int
    let residueCount: Int
    let sequenceKind: SequenceKind
    let selectedResidueCount: Int
    let selectedStartPosition: Int?
    let selectedEndPosition: Int?
    @Binding var backgroundMode: AlignmentBackgroundMode

    var body: some View {
        HStack(spacing: 12) {
            Label("\(sequenceCount) sequences", systemImage: "list.number")
            Label("\(residueCount) residues", systemImage: "ruler")
            Label(sequenceKind.rawValue, systemImage: "tag")
            Label("selected \(selectedResidueCount)", systemImage: "selection.pin.in.out")
            if let selectedStartPosition, let selectedEndPosition, selectedResidueCount > 0 {
                Label("pos \(selectedStartPosition)-\(selectedEndPosition)", systemImage: "arrow.left.and.right")
            }
            Spacer()
            Picker("Background", selection: $backgroundMode) {
                ForEach(AlignmentBackgroundMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.menu)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
