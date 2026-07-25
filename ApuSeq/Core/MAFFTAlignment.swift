import Foundation

enum MAFFTAlignmentError: LocalizedError {
    case executableNotFound
    case invalidInput
    case failed(status: Int32, message: String)
    case emptyOutput

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            return String(localized: "The bundled MAFFT executable could not be found.")
        case .invalidInput:
            return String(localized: "At least two sequences are required for MAFFT alignment.")
        case .failed(let status, let message):
            let detail = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if detail.isEmpty {
                return String(localized: "MAFFT failed with exit status \(status).")
            }
            return String(localized: "MAFFT failed with exit status \(status): \(detail)")
        case .emptyOutput:
            return String(localized: "MAFFT completed but did not produce an alignment.")
        }
    }
}

enum MAFFTAligner {
    nonisolated static func alignAuto(rawText: String) async throws -> String {
        let processBox = MAFFTProcessBox()
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) {
                try alignAutoSynchronously(rawText: rawText, processBox: processBox)
            }.value
        } onCancel: {
            processBox.terminate()
        }
    }

    nonisolated static func alignAuto(rows: [AlignmentRow]) async throws -> [AlignmentRow] {
        let processBox = MAFFTProcessBox()
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) {
                try alignAutoSynchronously(rows: rows, processBox: processBox)
            }.value
        } onCancel: {
            processBox.terminate()
        }
    }

    nonisolated private static func alignAutoSynchronously(rawText: String, processBox: MAFFTProcessBox) throws -> String {
        let alignment = try AlignmentParser.parse(rawText)
        let alignedRows = try alignAutoSynchronously(rows: alignment.rows, processBox: processBox)
        return AlignmentSerializer.serialize(rows: alignedRows, preferredFormat: .fasta)
    }

    nonisolated private static func alignAutoSynchronously(rows: [AlignmentRow], processBox: MAFFTProcessBox) throws -> [AlignmentRow] {
        guard rows.count >= 2 else {
            throw MAFFTAlignmentError.invalidInput
        }
        try Task.checkCancellation()

        let temporaryRows = rows.enumerated().map { index, row in
            AlignmentRow(name: temporaryName(for: index), sequence: row.sequence)
        }
        let fasta = AlignmentSerializer.serialize(rows: temporaryRows, preferredFormat: .fasta)
        let mafftURL = try bundledMAFFTScriptURL()
        let temporaryDirectory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        let inputURL = temporaryDirectory.appendingPathComponent("input.fasta")
        try fasta.write(to: inputURL, atomically: true, encoding: .utf8)

        let output = try runMAFFT(
            executableURL: mafftURL,
            inputURL: inputURL,
            temporaryDirectory: temporaryDirectory,
            processBox: processBox
        )
        try Task.checkCancellation()
        guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MAFFTAlignmentError.emptyOutput
        }
        let parsed = try AlignmentParser.parse(output)
        let sequencesByName = Dictionary(uniqueKeysWithValues: parsed.rows.map { ($0.name, $0.sequence) })
        return try rows.indices.map { index in
            let name = temporaryName(for: index)
            guard let sequence = sequencesByName[name] else {
                throw MAFFTAlignmentError.emptyOutput
            }
            return AlignmentRow(name: rows[index].name, sequence: sequence)
        }
    }

    nonisolated private static func temporaryName(for index: Int) -> String {
        "ApuSeq_Row_\(index)"
    }

    nonisolated private static func bundledMAFFTScriptURL() throws -> URL {
        let url = Bundle.main.resourceURL?
            .appendingPathComponent("MAFFT")
            .appendingPathComponent("mafftdir")
            .appendingPathComponent("bin")
            .appendingPathComponent("mafft")
        guard let url else {
            throw MAFFTAlignmentError.executableNotFound
        }
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw MAFFTAlignmentError.executableNotFound
        }
        return url
    }

    nonisolated private static func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ApuSeq-MAFFT-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    nonisolated private static func runMAFFT(
        executableURL: URL,
        inputURL: URL,
        temporaryDirectory: URL,
        processBox: MAFFTProcessBox
    ) throws -> String {
        try Task.checkCancellation()
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [executableURL.path, "--quiet", "--auto", inputURL.path]
        process.currentDirectoryURL = executableURL.deletingLastPathComponent()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        var environment = ProcessInfo.processInfo.environment
        environment["TMPDIR"] = temporaryDirectory.path
        environment["LANG"] = "C"
        environment["MAFFT_BINARIES"] = Bundle.main.bundleURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("Helpers")
            .appendingPathComponent("MAFFT")
            .appendingPathComponent("mafftdir")
            .appendingPathComponent("libexec")
            .path
        process.environment = environment

        processBox.set(process)
        defer {
            processBox.clear(process)
        }
        try process.run()

        let outputData = readDataAsynchronously(from: outputPipe.fileHandleForReading)
        let errorData = readDataAsynchronously(from: errorPipe.fileHandleForReading)
        process.waitUntilExit()

        let output = String(decoding: outputData(), as: UTF8.self)
        let errorMessage = String(decoding: errorData(), as: UTF8.self)
        try Task.checkCancellation()
        guard process.terminationStatus == 0 else {
            throw MAFFTAlignmentError.failed(status: process.terminationStatus, message: errorMessage)
        }
        return output
    }

    nonisolated private static func readDataAsynchronously(from fileHandle: FileHandle) -> () -> Data {
        let lock = NSLock()
        var data = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            let readData = fileHandle.readDataToEndOfFile()
            lock.lock()
            data = readData
            lock.unlock()
            group.leave()
        }
        return {
            group.wait()
            lock.lock()
            defer { lock.unlock() }
            return data
        }
    }
}

enum AlignmentRangeRealignmentError: LocalizedError {
    case invalidRange
    case insufficientNonEmptyRows
    case missingAlignedRow

    var errorDescription: String? {
        switch self {
        case .invalidRange:
            return String(localized: "Select one or more alignment columns to realign.")
        case .insufficientNonEmptyRows:
            return String(localized: "At least two selected sequences must contain residues in the selected columns.")
        case .missingAlignedRow:
            return String(localized: "MAFFT did not return all selected sequences.")
        }
    }
}

enum AlignmentRangeRealigner {
    typealias Aligner = @Sendable ([AlignmentRow]) async throws -> [AlignmentRow]

    nonisolated static func realignSelectedColumns(
        rows: [AlignmentRow],
        columnRange: Range<Int>,
        aligner: Aligner = MAFFTAligner.alignAuto(rows:)
    ) async throws -> [AlignmentRow] {
        guard !rows.isEmpty,
              columnRange.lowerBound >= 0,
              columnRange.lowerBound < columnRange.upperBound else {
            throw AlignmentRangeRealignmentError.invalidRange
        }
        let alignmentLength = rows.map { ($0.sequence as NSString).length }.max() ?? 0
        guard columnRange.upperBound <= alignmentLength else {
            throw AlignmentRangeRealignmentError.invalidRange
        }

        let fragments = rows.enumerated().map { index, row in
            RegionFragment(
                rowIndex: index,
                name: row.name,
                prefix: substring(row.sequence, start: 0, end: columnRange.lowerBound),
                selected: substring(row.sequence, start: columnRange.lowerBound, end: columnRange.upperBound),
                suffix: substring(row.sequence, start: columnRange.upperBound, end: alignmentLength)
            )
        }
        let nonEmptyFragments = fragments.compactMap { fragment -> AlignmentRow? in
            let sequence = degapped(fragment.selected)
            guard !sequence.isEmpty else { return nil }
            return AlignmentRow(name: temporaryName(for: fragment.rowIndex), sequence: sequence)
        }
        guard nonEmptyFragments.count >= 2 else {
            throw AlignmentRangeRealignmentError.insufficientNonEmptyRows
        }

        let alignedRows = try await aligner(nonEmptyFragments)
        let alignedByName = Dictionary(uniqueKeysWithValues: alignedRows.map { ($0.name, $0.sequence) })
        let alignedLength = alignedRows.map { ($0.sequence as NSString).length }.max() ?? 0

        return try fragments.map { fragment in
            let selectedSequence: String
            if degapped(fragment.selected).isEmpty {
                selectedSequence = String(repeating: "-", count: alignedLength)
            } else {
                guard let aligned = alignedByName[temporaryName(for: fragment.rowIndex)] else {
                    throw AlignmentRangeRealignmentError.missingAlignedRow
                }
                selectedSequence = aligned
            }
            return AlignmentRow(
                name: fragment.name,
                sequence: fragment.prefix + selectedSequence + fragment.suffix
            )
        }
    }

    private struct RegionFragment {
        let rowIndex: Int
        let name: String
        let prefix: String
        let selected: String
        let suffix: String
    }

    nonisolated private static func temporaryName(for index: Int) -> String {
        "ApuSeq_Row_\(index)"
    }

    nonisolated private static func degapped(_ sequence: String) -> String {
        sequence.filter { character in
            character != "-" && character != "."
        }
    }

    nonisolated private static func substring(_ sequence: String, start: Int, end: Int) -> String {
        let source = sequence as NSString
        let safeStart = min(max(start, 0), source.length)
        let safeEnd = min(max(end, safeStart), source.length)
        return source.substring(with: NSRange(location: safeStart, length: safeEnd - safeStart))
    }
}

private final class MAFFTProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var process: Process?

    nonisolated init() {}

    nonisolated func set(_ process: Process) {
        lock.lock()
        self.process = process
        lock.unlock()
    }

    nonisolated func clear(_ process: Process) {
        lock.lock()
        if self.process === process {
            self.process = nil
        }
        lock.unlock()
    }

    nonisolated func terminate() {
        lock.lock()
        let process = self.process
        lock.unlock()
        if process?.isRunning == true {
            process?.terminate()
        }
    }
}
