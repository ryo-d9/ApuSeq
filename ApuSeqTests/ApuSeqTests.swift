import Foundation
import Testing
import UniformTypeIdentifiers
@testable import ApuSeq

struct ApuSeqTests {
    @Test func parsesFASTANormalizesRowsAndInfersNucleotideKind() throws {
        let text = """
        >Beta
        AC
        GT
        >Alpha
        AC
        """

        let alignment = try AlignmentParser.parse(text)

        #expect(alignment.format == .fasta)
        #expect(alignment.length == 4)
        #expect(alignment.sequenceKind == .nucleotide)
        #expect(alignment.rows.map(\.name) == ["Beta", "Alpha"])
        #expect(alignment.rows.map(\.sequence) == ["ACGT", "AC--"])
    }

    @Test func parsesCLUSTALBlocksInOriginalSequenceOrder() throws {
        let text = """
        CLUSTAL W

        Seq1    ACGT
        Seq2    AC-T

        Seq1    TGCA
        Seq2    TG-A
        """

        let alignment = try AlignmentParser.parse(text)

        #expect(alignment.format == .clustal)
        #expect(alignment.rows.map(\.name) == ["Seq1", "Seq2"])
        #expect(alignment.rows.map(\.sequence) == ["ACGTTGCA", "AC-TTG-A"])
    }

    @Test func serializesRowsAsFASTAAndCLUSTAL() {
        let rows = [
            AlignmentRow(name: "Seq 1", sequence: "ACGT"),
            AlignmentRow(name: "Seq2", sequence: "A-GT")
        ]

        let fasta = AlignmentSerializer.serialize(rows: rows, preferredFormat: .fasta)
        let clustal = AlignmentSerializer.serialize(rows: rows, preferredFormat: .clustal)

        #expect(fasta == ">Seq 1\nACGT\n>Seq2\nA-GT\n")
        #expect(clustal.hasPrefix("CLUSTAL\n\n"))
        #expect(clustal.contains("Seq_1"))
        #expect(clustal.contains("A-GT"))
    }

    @Test func reverseComplementPreservesNamesAndHandlesAmbiguousBases() throws {
        let text = """
        >Mixed
        ACGTURYKMBVDH-.acgt
        """

        let output = try AlignmentReverseComplementer.reverseComplementFASTA(rawText: text)

        #expect(output == ">Mixed\nacgt.-DHBVKMRYAACGT")
    }

    @Test func reverseComplementRejectsAminoAcidAlignments() throws {
        let text = """
        >Protein
        MPEPTIDE
        """

        #expect(throws: AlignmentReverseComplementError.unsupportedSequenceKind) {
            try AlignmentReverseComplementer.reverseComplementFASTA(rawText: text)
        }
    }

    @Test func translatesNucleotideFASTAWithFramesAndCodonTables() throws {
        let text = """
        >Coding
        ATGAAATGATAA
        """

        let standard = try AlignmentTranslator.translateFASTA(
            rawText: text,
            frameOffset: 0,
            codonTable: .standard
        )
        let mitochondrial = try AlignmentTranslator.translateFASTA(
            rawText: text,
            frameOffset: 0,
            codonTable: .vertebrateMitochondrial
        )
        let shifted = try AlignmentTranslator.translateFASTA(
            rawText: text,
            frameOffset: 1,
            codonTable: .standard
        )

        #expect(standard == ">Coding\nMK**")
        #expect(mitochondrial == ">Coding\nMKW*")
        #expect(shifted == ">Coding\n*ND")
    }

    @Test func textDecodingReadsUTF8UTF16AndShiftJIS() throws {
        let utf8Data = Data("ACGT".utf8)
        let utf16Data = try #require("ACGT".data(using: .utf16LittleEndian))
        let shiftJISData = try #require("配列".data(using: .shiftJIS))

        #expect(TextDecoding.decode(utf8Data) == "ACGT")
        #expect(TextDecoding.decode(utf16Data) == "ACGT")
        #expect(TextDecoding.decode(shiftJISData) == "配列")
    }

    @Test func consensusIgnoresGapsAndFallsBackToGapForEmptyColumns() {
        let rows = [
            AlignmentRow(name: "A", sequence: "A-C"),
            AlignmentRow(name: "B", sequence: "AT-"),
            AlignmentRow(name: "C", sequence: "A--")
        ]

        let consensus = AlignmentStatistics.consensusSequence(rows: rows, length: 3)

        #expect(consensus == "ATC")
    }

    @Test func rendererComputesIdentityAndMajorityResiduesWhenRequested() throws {
        let rows = [
            AlignmentRow(name: "A", sequence: "ACG"),
            AlignmentRow(name: "B", sequence: "ATG"),
            AlignmentRow(name: "C", sequence: "A-G")
        ]
        let alignment = AlignmentData(format: .fasta, rows: rows, length: 3, sequenceKind: .nucleotide)

        let rendered = AlignmentRenderer.render(
            alignment,
            needsIdentityByColumn: true,
            needsMajorityResidueByColumn: true,
            fontSize: 12
        )

        #expect(rendered.identityByColumn.count == 3)
        #expect(abs(rendered.identityByColumn[0] - 1.0) < 0.001)
        #expect(abs(rendered.identityByColumn[1] - (1.0 / 3.0)) < 0.001)
        #expect(abs(rendered.identityByColumn[2] - 1.0) < 0.001)
        #expect(rendered.majorityResidueByColumn.compactMap(UnicodeScalar.init).map(String.init) == ["A", "C", "G"])
    }

    @Test func rendererSkipsColumnStatisticsWhenBackgroundDoesNotNeedThem() {
        let rows = [
            AlignmentRow(name: "A", sequence: "ACG"),
            AlignmentRow(name: "B", sequence: "ATG")
        ]
        let alignment = AlignmentData(format: .fasta, rows: rows, length: 3, sequenceKind: .nucleotide)

        let rendered = AlignmentRenderer.render(
            alignment,
            needsIdentityByColumn: false,
            needsMajorityResidueByColumn: false,
            fontSize: 12
        )

        #expect(rendered.identityByColumn.isEmpty)
        #expect(rendered.majorityResidueByColumn.isEmpty)
    }

    @Test func referenceDifferenceColoringNormalizesCaseAndGapCharacters() {
        #expect(ReferenceDifferencePalette.backgroundColor(for: 65, referenceResidue: 65) == nil)
        #expect(ReferenceDifferencePalette.backgroundColor(for: 97, referenceResidue: 65) == nil)
        #expect(ReferenceDifferencePalette.backgroundColor(for: 46, referenceResidue: 45) == nil)
        #expect(ReferenceDifferencePalette.backgroundColor(for: 67, referenceResidue: 65) != nil)
        #expect(ReferenceDifferencePalette.backgroundColor(for: 67, referenceResidue: nil) == nil)
    }

    @Test func upgmaOrderingGroupsMostSimilarRows() throws {
        let rows = [
            AlignmentRow(name: "Distant", sequence: "TTTT"),
            AlignmentRow(name: "Reference", sequence: "AAAA"),
            AlignmentRow(name: "Similar", sequence: "AAAT")
        ]

        let orderedNames = AlignmentClusterer.upgmaOrderedRows(rows).map(\.name)

        let referenceIndex = try #require(orderedNames.firstIndex(of: "Reference"))
        let similarIndex = try #require(orderedNames.firstIndex(of: "Similar"))
        #expect(abs(referenceIndex - similarIndex) == 1)
    }

    @Test func rowOrderingSortsNamesUsingLocalizedStandardCompare() {
        let rows = [
            AlignmentRow(name: "sample 10", sequence: "AAAA"),
            AlignmentRow(name: "sample 2", sequence: "CCCC"),
            AlignmentRow(name: "sample 1", sequence: "GGGG")
        ]

        let orderedRows = AlignmentRowOrdering.nameOrderedRows(rows)

        #expect(orderedRows.map(\.name) == ["sample 1", "sample 2", "sample 10"])
    }

    @Test func upgmaOrderingIsLimitedToThreeThroughThreeHundredRows() {
        let twoRows = (0..<2).map { AlignmentRow(name: "Row \($0)", sequence: "AC") }
        let threeHundredRows = (0..<300).map { AlignmentRow(name: "Row \($0)", sequence: "AC") }
        let threeHundredOneRows = (0..<301).map { AlignmentRow(name: "Row \($0)", sequence: "AC") }

        #expect(!AlignmentRowOrdering.canOrderWithUPGMA(rowCount: twoRows.count))
        #expect(AlignmentRowOrdering.canOrderWithUPGMA(rowCount: threeHundredRows.count))
        #expect(!AlignmentRowOrdering.canOrderWithUPGMA(rowCount: threeHundredOneRows.count))
        #expect(AlignmentRowOrdering.upgmaOrderedRows(threeHundredOneRows).map(\.name) == threeHundredOneRows.map(\.name))
    }

    @Test func allGapColumnRemovalRemovesOnlySharedGapColumns() throws {
        let rows = [
            AlignmentRow(name: "A", sequence: "A-.C"),
            AlignmentRow(name: "B", sequence: "T--G"),
            AlignmentRow(name: "C", sequence: "C-.T")
        ]

        let editedRows = try #require(AlignmentColumnEditor.removingAllGapColumns(from: rows, length: 4))

        #expect(editedRows.map(\.name) == ["A", "B", "C"])
        #expect(editedRows.map(\.sequence) == ["AC", "TG", "CT"])
    }

    @Test func allGapColumnRemovalLeavesNoOpAndAllGapAlignmentsUnchanged() {
        let noGapRows = [
            AlignmentRow(name: "A", sequence: "AC"),
            AlignmentRow(name: "B", sequence: "TG")
        ]
        let allGapRows = [
            AlignmentRow(name: "A", sequence: "-."),
            AlignmentRow(name: "B", sequence: "--")
        ]

        #expect(AlignmentColumnEditor.removingAllGapColumns(from: noGapRows, length: 2) == nil)
        #expect(AlignmentColumnEditor.removingAllGapColumns(from: allGapRows, length: 2) == nil)
    }

    @Test func trailingGapTrimRemovesOnlyTerminalGapCharacters() throws {
        let rows = [
            AlignmentRow(name: "A", sequence: "AC--"),
            AlignmentRow(name: "B", sequence: "A-C."),
            AlignmentRow(name: "C", sequence: "--AC")
        ]

        #expect(AlignmentColumnEditor.hasTrailingGaps(in: rows))
        let trimmedRows = try #require(AlignmentColumnEditor.trimmingTrailingGaps(from: rows))

        #expect(trimmedRows.map(\.name) == ["A", "B", "C"])
        #expect(trimmedRows.map(\.sequence) == ["AC", "A-C", "--AC"])
    }

    @Test func trailingGapTrimReturnsNilWhenNoRowsChange() {
        let rows = [
            AlignmentRow(name: "A", sequence: "AC"),
            AlignmentRow(name: "B", sequence: "-C")
        ]

        #expect(!AlignmentColumnEditor.hasTrailingGaps(in: rows))
        #expect(AlignmentColumnEditor.trimmingTrailingGaps(from: rows) == nil)
    }

    @Test func rowOnlyEditPadsAtRowEndsWithoutChangingOtherColumns() throws {
        let edited = try #require(
            AlignmentColumnEditor.replacingRowsOnly(
                in: ["ACGT", "ACGT"],
                edits: [
                    AlignmentColumnEditor.RowEdit(row: 1, column: 2, length: 0, replacement: "-")
                ]
            )
        )

        #expect(edited.length == 5)
        #expect(edited.sequences == ["ACGT-", "AC-GT"])
    }

    @Test func rowOnlyDeletionPadsEditedRowAtEnd() throws {
        let edited = try #require(
            AlignmentColumnEditor.replacingRowsOnly(
                in: ["ACGT", "A-GT"],
                edits: [
                    AlignmentColumnEditor.RowEdit(row: 1, column: 1, length: 1, replacement: "")
                ]
            )
        )

        #expect(edited.length == 4)
        #expect(edited.sequences == ["ACGT", "AGT-"])
    }

    @Test func gapColumnInsertionAddsGapToEveryRowAtColumn() throws {
        let rows = [
            AlignmentRow(name: "A", sequence: "ACGT"),
            AlignmentRow(name: "B", sequence: "A-GT")
        ]

        let editedRows = try #require(AlignmentColumnEditor.insertingGapColumn(in: rows, column: 2))

        #expect(editedRows.map(\.name) == ["A", "B"])
        #expect(editedRows.map(\.sequence) == ["AC-GT", "A--GT"])
    }

    @Test func selectedColumnRealignmentRestoresOnlySelectedRegion() async throws {
        let rows = [
            AlignmentRow(name: "A", sequence: "AAAC-CGG"),
            AlignmentRow(name: "B", sequence: "AAA---GG"),
            AlignmentRow(name: "C", sequence: "AAATTTGG")
        ]

        let realignedRows = try await AlignmentRangeRealigner.realignSelectedColumns(
            rows: rows,
            columnRange: 3..<6
        ) { rows in
            #expect(rows.map(\.name) == ["ApuSeq_Row_0", "ApuSeq_Row_2"])
            #expect(rows.map(\.sequence) == ["CC", "TTT"])
            return [
                AlignmentRow(name: "ApuSeq_Row_0", sequence: "C-C-"),
                AlignmentRow(name: "ApuSeq_Row_2", sequence: "TT-T")
            ]
        }

        #expect(realignedRows.map(\.name) == ["A", "B", "C"])
        #expect(realignedRows.map(\.sequence) == ["AAAC-C-GG", "AAA----GG", "AAATT-TGG"])
    }

    @Test func selectedColumnRealignmentRejectsInsufficientNonEmptyRows() async throws {
        let rows = [
            AlignmentRow(name: "A", sequence: "AAA---GG"),
            AlignmentRow(name: "B", sequence: "AAAC--GG")
        ]

        do {
            _ = try await AlignmentRangeRealigner.realignSelectedColumns(
                rows: rows,
                columnRange: 3..<6
            ) { rows in
                rows
            }
            Issue.record("Expected selected column realignment to reject one non-empty selected fragment")
        } catch AlignmentRangeRealignmentError.insufficientNonEmptyRows {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test @MainActor func viewModelRendersNameOrderWithoutChangingOriginalAlignment() async throws {
        let viewModel = AlignmentViewModel()
        viewModel.alignment = AlignmentData(
            format: .fasta,
            rows: [
                AlignmentRow(name: "sample 10", sequence: "AAAA"),
                AlignmentRow(name: "sample 2", sequence: "CCCC"),
                AlignmentRow(name: "sample 1", sequence: "GGGG")
            ],
            length: 4,
            sequenceKind: .nucleotide
        )

        viewModel.rerender(
            fontSize: 12,
            needsIdentityByColumn: false,
            needsMajorityResidueByColumn: false,
            displayOrderMode: .name,
            referenceName: nil
        )
        try await waitUntil { viewModel.contentVersion > 0 }

        #expect(viewModel.displayedRows.map(\.name) == ["sample 1", "sample 2", "sample 10"])
        #expect(viewModel.alignment.rows.map(\.name) == ["sample 10", "sample 2", "sample 1"])
        #expect(viewModel.renderedDisplayOrderMode == .name)
    }

    @Test func documentSnapshotReturnsCurrentRawText() throws {
        let rawText = ">Seq1\nACGT\n"
        let document = ApuSeqDocument(rawText: rawText)

        let snapshot = try document.snapshot(contentType: .plainText)

        #expect(snapshot == rawText)

        document.rawText = ">Seq2\nTGCA\n"
        #expect(try document.snapshot(contentType: .plainText) == ">Seq2\nTGCA\n")
    }

    @MainActor
    private func waitUntil(
        timeout: Duration = .seconds(2),
        condition: @MainActor @escaping () -> Bool
    ) async throws {
        let start = ContinuousClock.now
        while !condition() {
            if ContinuousClock.now - start > timeout {
                Issue.record("Timed out waiting for asynchronous rendering")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
