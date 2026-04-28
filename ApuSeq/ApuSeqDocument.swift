//
//  ApuSeqDocument.swift
//  ApuSeq
//
//  Created by 須田崚 on 2026/04/27.
//

import SwiftUI
import UniformTypeIdentifiers

struct ApuSeqDocument: FileDocument {
    var rawText: String
    var suggestedSaveFilename: String?
    var markEditedOnFirstDisplay: Bool

    init(
        rawText: String = "",
        suggestedSaveFilename: String? = nil,
        markEditedOnFirstDisplay: Bool = false
    ) {
        self.rawText = rawText
        self.suggestedSaveFilename = suggestedSaveFilename
        self.markEditedOnFirstDisplay = markEditedOnFirstDisplay
    }

    // Keep runtime type handling aligned with Info.plist declarations.
    static let readableContentTypes: [UTType] = [
        UTType(importedAs: "com.apuseq.fasta"),
        UTType(importedAs: "org.clustal"),
        UTType(importedAs: "com.apuseq.plain-text"),
        .plainText,
        .text
    ]

    static let writableContentTypes: [UTType] = [
        UTType(importedAs: "com.apuseq.fasta"),
        UTType(importedAs: "org.clustal"),
        UTType(importedAs: "com.apuseq.plain-text"),
        .plainText
    ]

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }

        if let decoded = TextDecoding.decode(data) {
            rawText = decoded
            suggestedSaveFilename = nil
            markEditedOnFirstDisplay = false
            return
        }
        rawText = String(decoding: data, as: UTF8.self)
        suggestedSaveFilename = nil
        markEditedOnFirstDisplay = false
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = rawText.data(using: .utf8)!
        return .init(regularFileWithContents: data)
    }
}
