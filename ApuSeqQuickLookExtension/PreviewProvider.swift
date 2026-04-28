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
        let previewText = limitedPreviewText(from: rawText, lineLimit: 400)
        let escaped = previewText
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

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
        </style>
        </head>
        <body>
        <pre>\(escaped)</pre>
        </body>
        </html>
        """
    }

    private func limitedPreviewText(from text: String, lineLimit: Int) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > lineLimit else { return text }
        let head = lines.prefix(lineLimit).joined(separator: "\n")
        return "\(head)\n\n... (preview truncated: showing first \(lineLimit) lines)"
    }
}
