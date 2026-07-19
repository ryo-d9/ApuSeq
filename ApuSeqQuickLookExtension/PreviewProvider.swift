import CoreGraphics
import Foundation
import QuickLookUI
import UniformTypeIdentifiers

final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(
        for request: QLFilePreviewRequest,
        completionHandler: @escaping @Sendable (QLPreviewReply?, (any Error)?) -> Void
    ) {
        do {
            let data = try Data(contentsOf: request.fileURL)
            let text = try decodeText(from: data)
            let html = htmlPreview(for: text)

            let reply = QLPreviewReply(
                dataOfContentType: .html,
                contentSize: CGSize(width: 1200, height: 900)
            ) { _ in
                guard let encoded = html.data(using: .utf8) else {
                    throw CocoaError(.fileReadUnknown)
                }
                return encoded
            }
            completionHandler(reply, nil)
        } catch {
            completionHandler(nil, error)
        }
    }

    private func decodeText(from data: Data) throws -> String {
        if let decoded = TextDecoding.decode(data) {
            return decoded
        }
        throw CocoaError(.fileReadCorruptFile)
    }

    private func htmlPreview(for rawText: String) -> String {
        let previewText = limitedPreviewText(from: rawText, lineLimit: 400, lineLengthLimit: 5_000)
        let highlighted = highlightedHTML(for: previewText)

        return """
        <!doctype html>
        <html>
        <head>
        <meta charset=\"utf-8\" />
        <style>
        :root {
            color-scheme: light dark;
        }
        body {
            margin: 0;
            padding: 14px;
            font: 12px SF Mono, Menlo, Monaco, monospace;
            line-height: 1.35;
            background: transparent;
        }
        pre {
            margin: 0;
            white-space: pre;
        }
        .res-a { background: rgba(52, 199, 89, 0.22); }
        .res-c { background: rgba(0, 122, 255, 0.22); }
        .res-g { background: rgba(255, 149, 0, 0.22); }
        .res-tu { background: rgba(255, 59, 48, 0.22); }
        .res-rkh { background: rgba(175, 82, 222, 0.22); }
        .res-de { background: rgba(255, 45, 85, 0.22); }
        .res-snq { background: rgba(90, 200, 250, 0.22); }
        .res-hydrophobic { background: rgba(162, 132, 94, 0.22); }
        .res-other { background: rgba(142, 142, 147, 0.18); }
        </style>
        </head>
        <body>
        <pre>\(highlighted)</pre>
        </body>
        </html>
        """
    }

    private func highlightedHTML(for text: String) -> String {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { highlightedLineHTML(for: String($0)) }
            .joined(separator: "\n")
    }

    private func highlightedLineHTML(for line: String) -> String {
        guard !line.hasPrefix(">") else {
            return escapedHTML(line)
        }

        if let firstWhitespace = line.firstIndex(where: { $0.isWhitespace }),
           line[..<firstWhitespace].contains(where: { !$0.isWhitespace }) {
            let prefix = String(line[...firstWhitespace])
            let sequenceStart = line.index(after: firstWhitespace)
            let sequence = String(line[sequenceStart...])
            return escapedHTML(prefix) + highlightedResiduesHTML(for: sequence)
        }

        return highlightedResiduesHTML(for: line)
    }

    private func highlightedResiduesHTML(for text: String) -> String {
        var fragments: [String] = []
        fragments.reserveCapacity(text.count)

        for character in text {
            let escaped = escapedHTML(String(character))
            if let cssClass = residueCSSClass(for: character) {
                fragments.append("<span class=\"\(cssClass)\">\(escaped)</span>")
            } else {
                fragments.append(escaped)
            }
        }

        return fragments.joined()
    }

    private func residueCSSClass(for residue: Character) -> String? {
        switch residue.uppercased().first {
        case "A":
            return "res-a"
        case "C":
            return "res-c"
        case "G":
            return "res-g"
        case "T", "U":
            return "res-tu"
        case "R", "K", "H":
            return "res-rkh"
        case "D", "E":
            return "res-de"
        case "S", "N", "Q":
            return "res-snq"
        case "F", "W", "Y", "L", "I", "V", "M":
            return "res-hydrophobic"
        case "P", "X", "B", "Z", "J", "O":
            return "res-other"
        default:
            return nil
        }
    }

    private func escapedHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func limitedPreviewText(from text: String, lineLimit: Int, lineLengthLimit: Int) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let visibleLines = lines.prefix(lineLimit)
        let truncatedLines = visibleLines.map { limitedLineText(from: String($0), limit: lineLengthLimit) }
        var preview = truncatedLines.joined(separator: "\n")

        if lines.count > lineLimit {
            preview += "\n\n... (preview truncated: showing first \(lineLimit) lines)"
        }

        return preview
    }

    private func limitedLineText(from line: String, limit: Int) -> String {
        guard line.count > limit else { return line }

        let endIndex = line.index(line.startIndex, offsetBy: limit)
        return String(line[..<endIndex]) + " ... (line truncated)"
    }
}
