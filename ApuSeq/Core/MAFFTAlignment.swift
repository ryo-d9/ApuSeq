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

    nonisolated private static func alignAutoSynchronously(rawText: String, processBox: MAFFTProcessBox) throws -> String {
        let alignment = try AlignmentParser.parse(rawText)
        guard alignment.rows.count >= 2 else {
            throw MAFFTAlignmentError.invalidInput
        }
        try Task.checkCancellation()

        let fasta = AlignmentSerializer.serialize(rows: alignment.rows, preferredFormat: .fasta)
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
        _ = try AlignmentParser.parse(output)
        return output
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
