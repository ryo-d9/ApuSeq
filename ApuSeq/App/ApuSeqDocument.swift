//
//  ApuSeqDocument.swift
//  ApuSeq
//
//  Created by Ryo A Suda on 2026/04/27.
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
        var pendingAlignment: AlignmentData?
    }

    private let lock = NSLock()
    private var storage: Storage

    var rawText: String {
        get { withLockedStorage { $0.rawText } }
        set {
            updateStorage {
                $0.rawText = newValue
                $0.pendingAlignment = nil
            }
        }
    }

    init(rawText: String = "") {
        storage = Storage(rawText: rawText, pendingAlignment: nil)
    }

    // Keep runtime type handling aligned with Info.plist declarations.
    static let readableContentTypes: [UTType] = [
        .fasta,
        .clustal,
        .plainText,
        .text
    ]

    static let writableContentTypes: [UTType] = [
        .fasta,
        .clustal,
        .plainText
    ]

    required init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let decoded = TextDecoding.decode(data) ?? String(decoding: data, as: UTF8.self)
        storage = Storage(rawText: decoded, pendingAlignment: nil)
    }

    func snapshot(contentType: UTType) throws -> String {
        let snapshotSource = withLockedStorage { storage in
            (storage.rawText, storage.pendingAlignment)
        }
        if let pendingAlignment = snapshotSource.1 {
            return AlignmentSerializer.serialize(
                rows: pendingAlignment.rows,
                preferredFormat: pendingAlignment.format
            )
        }
        return snapshotSource.0
    }

    func stageForSerialization(_ alignment: AlignmentData) {
        updateStorage { $0.pendingAlignment = alignment }
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
    static let clustal = UTType("org.clustal") ?? UTType(importedAs: "org.clustal")
}
