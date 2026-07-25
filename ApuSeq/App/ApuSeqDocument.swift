//
//  ApuSeqDocument.swift
//  ApuSeq
//
//  Created by Ryo Suda on 2026/04/27.
//

import Combine
import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers

@Observable
final class ApuSeqDocument: ReferenceFileDocument, @unchecked Sendable {
    typealias Snapshot = String

    // ReferenceFileDocument still requires ObservableObject; Observation drives SwiftUI reads.
    @ObservationIgnored
    let objectWillChange = ObservableObjectPublisher()

    private struct Storage {
        var rawText: String
    }

    private let lock = NSLock()
    private var storage: Storage

    var rawText: String {
        get { withLockedStorage { $0.rawText } }
        set { updateStorage { $0.rawText = newValue } }
    }

    init(rawText: String = "") {
        storage = Storage(rawText: rawText)
    }

    // Keep runtime type handling aligned with Info.plist declarations.
    static let readableContentTypes: [UTType] = [
        .fasta,
        .aliviewFA,
        .aliviewFAS,
        .aliviewFASTA,
        .clustal,
        .plainText,
        .text
    ]

    static let writableContentTypes: [UTType] = [
        .fasta,
        .aliviewFA,
        .aliviewFAS,
        .aliviewFASTA,
        .clustal,
        .plainText
    ]

    required init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let decoded = TextDecoding.decode(data) ?? String(decoding: data, as: UTF8.self)
        storage = Storage(rawText: decoded)
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
    static let fasta = UTType("org.fasta") ?? UTType(importedAs: "org.fasta")
    static let aliviewFA = UTType("aliview.fa") ?? UTType(importedAs: "aliview.fa")
    static let aliviewFAS = UTType("aliview.fas") ?? UTType(importedAs: "aliview.fas")
    static let aliviewFASTA = UTType("aliview.fasta") ?? UTType(importedAs: "aliview.fasta")
    static let clustal = UTType("org.clustal") ?? UTType(importedAs: "org.clustal")
}
