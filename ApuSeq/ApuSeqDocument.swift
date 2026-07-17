//
//  ApuSeqDocument.swift
//  ApuSeq
//
//  Created by 須田崚 on 2026/04/27.
//

import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

final class ApuSeqDocument: ReferenceFileDocument, @unchecked Sendable {
    typealias Snapshot = String

    let objectWillChange = ObservableObjectPublisher()

    private struct Storage {
        var rawText: String
        var suggestedSaveFilename: String?
        var markEditedOnFirstDisplay: Bool
    }

    private let lock = NSLock()
    private var storage: Storage

    var rawText: String {
        get { withLockedStorage { $0.rawText } }
        set { updateStorage { $0.rawText = newValue } }
    }

    var suggestedSaveFilename: String? {
        get { withLockedStorage { $0.suggestedSaveFilename } }
        set { updateStorage { $0.suggestedSaveFilename = newValue } }
    }

    var markEditedOnFirstDisplay: Bool {
        get { withLockedStorage { $0.markEditedOnFirstDisplay } }
        set { updateStorage { $0.markEditedOnFirstDisplay = newValue } }
    }

    init(
        rawText: String = "",
        suggestedSaveFilename: String? = nil,
        markEditedOnFirstDisplay: Bool = false
    ) {
        storage = Storage(
            rawText: rawText,
            suggestedSaveFilename: suggestedSaveFilename,
            markEditedOnFirstDisplay: markEditedOnFirstDisplay
        )
    }

    // Keep runtime type handling aligned with Info.plist declarations.
    static let readableContentTypes: [UTType] = [
        .apuSeqFASTA,
        .fasta,
        .clustal,
        .plainText,
        .text
    ]

    static let writableContentTypes: [UTType] = [
        .apuSeqFASTA,
        .fasta,
        .clustal,
        .plainText
    ]

    required init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let decoded = TextDecoding.decode(data) ?? String(decoding: data, as: UTF8.self)
        storage = Storage(
            rawText: decoded,
            suggestedSaveFilename: nil,
            markEditedOnFirstDisplay: false
        )
    }

    func snapshot(contentType: UTType) throws -> String {
        rawText
    }

    func fileWrapper(snapshot: String, configuration: WriteConfiguration) throws -> FileWrapper {
        let data = Data(snapshot.utf8)
        return .init(regularFileWithContents: data)
    }

    private func withLockedStorage<T>(_ body: (Storage) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(storage)
    }

    private func updateStorage(_ body: (inout Storage) -> Void) {
        objectWillChange.send()
        lock.lock()
        body(&storage)
        lock.unlock()
    }
}

private extension UTType {
    static let apuSeqFASTA = UTType("com.apuseq.fasta") ?? UTType(exportedAs: "com.apuseq.fasta")
    static let fasta = UTType("org.fasta") ?? UTType(importedAs: "org.fasta")
    static let clustal = UTType("org.clustal") ?? UTType(importedAs: "org.clustal")
}
